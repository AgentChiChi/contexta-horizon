#!/bin/bash
# Static checks of the Horizon sources and the built binary: what the app cannot do, by its own text.
#   bash tests/static-checks.sh        (run from the project folder; build.sh runs it after compiling)
cd "$(dirname "$0")/.."
APP_SRC="Sources/Core.swift Sources/App.swift Sources/Simple.swift Sources/MailAdapter.swift"   # the app itself (SelfTest.swift only makes synthetic fixtures)
BIN="dist/contexta-horizon.app/Contents/MacOS/ContextaHorizon"
pass=0; fail=0
check() { if [ "$2" = "ok" ]; then pass=$((pass+1)); echo "PASS $1  $3"; else fail=$((fail+1)); echo "FAIL $1  $3"; echo "       → $4"; fi; }
count() { grep -E -c "$1" $2 | awk -F: '{s+=$NF} END {print s+0}'; }
code() { sed -E 's://.*$::' $1; }                          # without line comments

n=$(code "$APP_SRC Sources/SelfTest.swift" | grep -E -c 'URLSession|URLRequest|NSURLConnection|NWConnection|NWListener|CFNetwork|CFStream|import Network|WebKit|WKWebView|socket\(|https?://|NSSharingService|MFMail|OSAScript|NSUserAppleScriptTask|CoreML|NaturalLanguage|MLModel|openai|anthropic')
check C01 "$([ "$n" = 0 ] && echo ok)" "no network, web view, sharing or model API anywhere in the sources (no URLSession, sockets, WebKit, web addresses, CoreML or model clients)" "$n matches"

libs=$(otool -L "$BIN" 2>/dev/null | grep -E -c 'Network\.framework|WebKit|CFNetwork|Security\.framework|Contacts|EventKit|MailKit')
check C02 "$([ -x "$BIN" ] && [ "$libs" = 0 ] && echo ok)" "the built binary links no Network, WebKit, CFNetwork, Security, Contacts, EventKit or mail framework" "$libs"

pb=$(code "$APP_SRC" | grep -c 'NSPasteboard')
inside=$(awk '/@objc private func copyShown\(\)/,/^    }/' Sources/Simple.swift | grep -c 'NSPasteboard')
guarded=$(awk '/@objc private func copyShown\(\)/,/^    }/' Sources/Simple.swift | grep -c 'guard copyButton.isEnabled, !shownText.isEmpty, preview.string == shownText else { return }\|board.setString(shownText, forType: .string)')
wired=$(code "$APP_SRC" | grep -c '#selector(copyShown)')
calls=$(code "$APP_SRC" | grep -c 'copyShown()')
onlyWhenOff=$(code Sources/Simple.swift | grep -c 'func smokePressCopyWhileDisabled() { if !copyButton.isEnabled { copyShown() } }')
keyEq=$(code "$APP_SRC" | grep -c 'copyButton.keyEquivalent')
returnCopies=$(awk '/func control\(_ control: NSControl, textView/,/^    }/' Sources/Simple.swift | grep -c 'copyShown\|NSPasteboard')
sheets=$(code "$APP_SRC" | grep -c 'beginSheet\|NSPopover\|runModal() == .OK, let copy')
reads=$(code "$APP_SRC" | grep -E -c 'string\(forType|readObjects|pasteboardItems|data\(forType|changeCount')
check C03 "$([ "$pb" = 1 ] && [ "$inside" = 1 ] && [ "$guarded" = 2 ] && [ "$wired" = 1 ] && [ "$calls" = 2 ] && [ "$onlyWhenOff" = 1 ] && [ "$keyEq" = 0 ] && [ "$returnCopies" = 0 ] && [ "$sheets" = 0 ] && [ "$reads" = 0 ] && echo ok)" "one clipboard path: the Copy button on the simple screen is the only place the clipboard is written, with exactly the text the inline preview shows, and only while that button is enabled; Return in the field never copies, the button has no key shortcut, there is no second sheet, and the clipboard is never read" "NSPasteboard=$pb inside=$inside guarded=$guarded wired=$wired calls=$calls keyEq=$keyEq returnCopies=$returnCopies sheets=$sheets reads=$reads"

proc=$(code "$APP_SRC" | grep -E -c 'Process\(\)|NSTask|posix_spawn|system\(|popen\(|execv|NSWorkspace\.shared\.open|openApplication|launchApplication')
fixed=$(code Sources/Core.swift | grep -E -c 'p\.executableURL = url$|p\.arguments = \[\]$')
calls=$(code Sources/App.swift | grep -c 'RefreshTool\.run(')
order=$(awk '/@objc private func runTool\(\)/,/^    }/' Sources/App.swift | grep -n -E 'let tool = places\.refreshTool|guard confirm\.runModal\(\) == \.alertSecondButtonReturn|RefreshTool\.run\(tool\)' | cut -d: -f1 | tr '\n' ' ')
sorted=$(echo $order | tr ' ' '\n' | sort -n | tr '\n' ' ')
check C04 "$([ "$proc" = 1 ] && [ "$fixed" = 2 ] && [ "$calls" = 1 ] && [ "$(echo $order | wc -w | tr -d ' ')" = 3 ] && [ "$order" = "$sorted" ] && echo ok)" "one program can be started, in one place: the fixed ~/WorkIndex/horizon-tools/refresh.command, with no arguments, only from the \"Refresh Feeds…\" action and only after its confirmation; nothing else is opened or launched" "Process=$proc fixed=$fixed calls=$calls order=$order"

fromData=$(code "$APP_SRC" | grep -E -c 'executableURL = .*(locator|path|row|evidence)|URL\(fileURLWithPath: .*(locator|\.path\b.*evidence)')
check C05 "$([ "$fromData" = 0 ] && grep -q 'workIndex.appendingPathComponent("horizon-tools/refresh.command")' Sources/Core.swift && echo ok)" "no path that comes from data is ever executed or opened: the tool's place is built from the home folder alone" "$fromData"

writes=$(code "$APP_SRC" | grep -E -c '\.write\(to:|createFile\(|FileHandle\(forWritingAtPath|FileHandle\(forUpdating|moveItem|copyItem|replaceItem|removeItem|trashItem|rename\(')
excl=$(code Sources/Core.swift | grep -c 'open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)')
opens=$(code "$APP_SRC" | grep -E -c '[^a-zA-Z]open\(')
links=$(code Sources/Core.swift | grep -c 'guard link(temporary.path, target.path) == 0')
unlinks=$(code "$APP_SRC" | grep -E -c '[^a-zA-Z]unlink\(')
onlyTemp=$(code Sources/Core.swift | grep -c 'defer { unlink(temporary.path) }')
check C06 "$([ "$writes" = 0 ] && [ "$excl" = 1 ] && [ "$opens" = 1 ] && [ "$links" = 1 ] && [ "$unlinks" = 1 ] && [ "$onlyTemp" = 1 ] && echo ok)" "the app writes one kind of file, atomically: a NEW import file written under a temporary name (O_CREAT|O_EXCL, 0600), synced, then linked to its final name (link fails rather than replace); only its own temporary file is ever removed; no source file is moved, renamed over or deleted" "writes=$writes excl=$excl opens=$opens links=$links unlinks=$unlinks"

defaults=$(code "$APP_SRC" | grep -c 'UserDefaults')
check C07 "$([ "$defaults" = 1 ] && grep -q 'private let d = UserDefaults.standard' Sources/Core.swift && echo ok)" "settings are kept in the app's own defaults only (the window length and the source switches)" "$defaults"

ui=0; for s in 'withTitle: "Open Work Context"' 'labels: ["3 months", "6 months", "Custom"]' 'NSButton(title: "Reread Sources"' 'NSButton(title: "Import…"' '"Evidence — '; do grep -qF "$s" Sources/App.swift && ui=$((ui+1)); done
for s in 'label("What do you want to continue?"' 'NSButton(title: "Copy"' 'NSButton(title: "Sources & Settings"'; do grep -qF "$s" Sources/Simple.swift && ui=$((ui+1)); done
id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Info.plist 2>/dev/null)
check C08 "$([ "$ui" = 8 ] && [ "$id" = "local.workindex.horizon" ] && echo ok)" "the English interface is there as real controls (Open Work Context, 3 months / 6 months / Custom, Reread Sources, Import…, Evidence; What do you want to continue?, Copy, Sources & Settings) and the bundle ID is local.workindex.horizon" "ui=$ui id=$id"

auto=$(code "Sources/App.swift Sources/Simple.swift" | grep -E -c 'Timer|DispatchSourceTimer|NSBackgroundActivityScheduler|asyncAfter|FSEvent|DispatchSource\.makeFileSystemObjectSource|NSMetadataQuery')
check C09 "$([ "$auto" = 0 ] && echo ok)" "nothing runs on a timer, in the background or on a file watcher: sources are read when a window first opens and on \"Reread Sources\"" "$auto"

as=$(code "$APP_SRC" | grep -c 'NSAppleScript(')
asWhere=$(code Sources/MailAdapter.swift | grep -c 'NSAppleScript(source: source)')
opensApp=$(code "$APP_SRC" | grep -E -c 'launchApplication|openApplication|NSWorkspace\.shared\.launch|\.activate\(options|open -a')
gate=$(awk '/static func collect\(isRunning/,/^    }/' Sources/MailAdapter.swift | grep -n -E 'guard isRunning\(\) else|let allowed = permission\(\)|guard allowed == 0 else|run\(script\(cap: cap\)\)' | cut -d: -f1 | tr '\n' ' ')
gateSorted=$(echo $gate | tr ' ' '\n' | sort -n | tr '\n' ' ')
mailCalls=$(code Sources/App.swift | grep -c 'MailAdapter.collect(')
mailOrder=$(awk '/@objc private func collectFromMail\(\)/,/^    }/' Sources/App.swift | grep -n -E 'guard confirm\.runModal\(\) == \.alertSecondButtonReturn|guard MailAdapter\.liveIsRunning\(\) else|MailAdapter\.livePermission\(\)|MailAdapter\.collect\(' | cut -d: -f1 | tr '\n' ' ')
mailSorted=$(echo $mailOrder | tr ' ' '\n' | sort -n | tr '\n' ' ')
check C10 "$([ "$as" = 1 ] && [ "$asWhere" = 1 ] && [ "$opensApp" = 0 ] && [ "$(echo $gate | wc -w | tr -d ' ')" = 5 ] && [ "$gate" = "$gateSorted" ] && [ "$mailCalls" = 1 ] && [ "$(echo $mailOrder | wc -w | tr -d ' ')" = 4 ] && [ "$mailOrder" = "$mailSorted" ] && echo ok)" "the Mac Mail adapter is the only AppleScript use, with a fixed script: it runs only from its own button, after the confirmation, after checking that Mail is already running and that macOS allows it; no code starts or activates another app" "NSAppleScript=$as where=$asWhere opensApp=$opensApp gate=$gate mailOrder=$mailOrder"

model=$(code "$APP_SRC" | grep -E -i -c 'injection|autofill|CGEvent|AXUIElement|addGlobalMonitor|NSEvent\.addLocalMonitor|keyDown')
check C11 "$([ "$model" = 0 ] && grep -qF 'title counts are signals, not proof of completed work' Sources/Core.swift && grep -qF 'titles are signals, not proof of completed work' Sources/Core.swift && grep -q 'static let maxCitations = 6' Sources/Core.swift && echo ok)" "no always-on model and no injection: nothing types, pastes or watches keys in other apps; the handoff is capped at 6 citations and says titles are signals, not completed outcomes" "$model"

launch=$(awk '/func applicationDidFinishLaunching/,/^    }/' Sources/App.swift | grep -c 'simple.show()')
left=$(awk '/@objc private func statusClicked\(\)/,/^    }/' Sources/App.swift | grep -c '} else { simple?.show() }')
right=$(awk '/@objc private func statusClicked\(\)/,/^    }/' Sources/App.swift | grep -c 'event?.type == .rightMouseUp')
dashOpens=$(code "Sources/App.swift Sources/Simple.swift" | grep -E -c 'dashboard\??\.show\(\)')
optIn=$(code Sources/Simple.swift | grep -E -c 'Importer\.|RefreshTool\.|MailAdapter\.|NSOpenPanel|NSDatePicker|NSSegmentedControl|NSPopUpButton|preferences\.')
local=$(code Sources/Core.swift | awk '/^enum Search/,/^}/' | grep -E -c 'Date\(\)|random|shuffled|UUID|Locale\.current')
check C12 "$([ "$launch" = 1 ] && [ "$left" = 1 ] && [ "$right" = 1 ] && [ "$dashOpens" = 2 ] && [ "$optIn" = 0 ] && [ "$local" = 0 ] && echo ok)" "the everyday path is the simple screen: it opens at launch and on a left click of the menu-bar icon (right click: the menu with Quit); it has no date, mode or model control and starts no import, refresh or Mail collection — those stay in the dashboard, opened only from the Sources & Settings link or the menu; the topic search uses no clock, randomness or locale" "launch=$launch left=$left right=$right dashOpens=$dashOpens optIn=$optIn local=$local"

byKey=$(code Sources/App.swift | grep -c '@objc private func useInSimple() { if let t = selected { onUseTopic?(t.key) } }')
kept=$(code Sources/App.swift | grep -c 'if let k = keep, let i = topics.firstIndex(where: { $0.key == k })')
byRow=$(code "Sources/App.swift Sources/Simple.swift Sources/SelfTest.swift" | grep -E -c 'smokeSelect\([0-9]|smokeSelect\(_ row|isKeyWindow|isMainWindow')
check C13 "$([ "$byKey" = 1 ] && [ "$kept" = 1 ] && [ "$byRow" = 0 ] && echo ok)" "the dashboard hands a topic to the simple screen by the selected topic's key, and keeps its selection by key when the period or switches reorder the rows; the tests select topics by key too (never by a fixed row) and do not depend on a window being the key window" "byKey=$byKey kept=$kept byRow=$byRow"

# English-only interface. Korean is left in Core.swift only as DATA the app must keep understanding (words of existing
# indexes, feeds and imports, Korean search fillers and particles, localized Gmail labels, Korean in file-name slugs).
hangulUI=$(LC_ALL=en_US.UTF-8 grep -c '[가-힣ㄱ-ㅎ]' Sources/App.swift Sources/Simple.swift Sources/MailAdapter.swift Info.plist build.sh | awk -F: '{s+=$NF} END {print s+0}')
hangulCore=$(LC_ALL=en_US.UTF-8 grep '[가-힣]' Sources/Core.swift | grep -v -E '^ +"기타", |datePattern = |"sunday", "회의"|\(re\|fw\|fwd\|답장\|전달\)|s\.contains\("부분"\)|static let filler: Set<String> = \["이어서"|"header", "이메일", "경로", "링크", "헤더"\]|private static let particles = \[|labels\.contains\("보낸"\)|\[\^a-z0-9가-힣\]' | wc -l | tr -d ' ')
compat=$(LC_ALL=en_US.UTF-8 grep -c -E 's\.contains\("부분"\)|labels\.contains\("보낸"\)|private static let particles = \["으로"|"스냅샷", "가져온 자료"|"이메일", "경로", "링크", "헤더"' Sources/Core.swift)
private=$(grep -i -c -E 'not for distribution|private local preview|private preview|비공개' Sources/Core.swift Sources/App.swift Sources/Simple.swift Sources/MailAdapter.swift Info.plist build.sh | awk -F: '{s+=$NF} END {print s+0}')
ver=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist 2>/dev/null); build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist 2>/dev/null); region=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDevelopmentRegion' Info.plist 2>/dev/null)
usage=$(/usr/libexec/PlistBuddy -c 'Print :NSAppleEventsUsageDescription' Info.plist 2>/dev/null | grep -c 'Collect from Mail')
check C14 "$([ "$hangulUI" = 0 ] && [ "$hangulCore" = 0 ] && [ "$compat" = 5 ] && [ "$private" = 0 ] && [ "$ver" = "0.4.1" ] && [ "$build" = 5 ] && [ "$region" = "en" ] && [ "$usage" = 1 ] && echo ok)" "public English build: no Korean text in the windows, menu, Mail messages, Info.plist or build script; the only Korean left in Core.swift is data the app must still understand (existing labels, search fillers and particles, a localized Gmail label, the \"부분\" coverage note); no private or not-for-distribution wording; version 0.4.1 (5), English development region, and the Mail permission text names the button that asks" "hangulUI=$hangulUI hangulCore=$hangulCore compat=$compat private=$private ver=$ver build=$build region=$region usage=$usage"

# The example mailbox: made-up data only, and a generator that touches nothing but its own output file.
S="Examples/sample-mail.mbox"
msgs=$(grep -c '^From sample@example.com ' "$S" 2>/dev/null); subj=$(grep -c '^Subject: ' "$S" 2>/dev/null); ids=$(grep -c '^Message-ID: <sample-[0-9][0-9]-[0-9]\{8\}@example.com>$' "$S" 2>/dev/null)
foreign=$(grep -o -E '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+' "$S" 2>/dev/null | grep -v -c '@example\.com$')
other=$(grep -v -E '^(From sample@example\.com |X-Gmail-Labels: (Inbox|Sent)$|From: [A-Z][a-z]+ Example <[a-z]+@example\.com>$|To: [A-Z][a-z]+ Example <[a-z]+@example\.com>$|Subject: |Date: |Message-ID: |This is a made-up message for trying Contexta Horizon\. It describes no real person, company or event\.$|$)' "$S" 2>/dev/null | wc -l | tr -d ' ')
gen=$(sed -E 's:^ *#.*$::' Examples/make-sample.sh | grep -E -c 'curl|wget|https?://|osascript|sudo|\$HOME|~/|defaults |security |mdfind|find /|rm -r')
check C15 "$([ "${msgs:-0}" -ge 8 ] && [ "$msgs" = "$subj" ] && [ "$msgs" = "$ids" ] && [ "$foreign" = 0 ] && [ "$other" = 0 ] && [ "$gen" = 0 ] && [ -f Examples/README.txt ] && echo ok)" "the example mailbox is made-up data only: every message has a subject and its own id, every address is at example.com, there is no line beyond the known headers and one fixed body sentence; its generator reads nothing from this Mac, uses no network and writes only its output file" "messages=$msgs subjects=$subj ids=$ids foreign=$foreign other=$other generator=$gen"

echo
echo "== $pass/$((pass+fail)) static checks passed =="
[ "$fail" = 0 ]
