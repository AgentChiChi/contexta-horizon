#!/bin/bash
# Static checks of the Horizon sources and the built binary: what the app cannot do, by its own text.
#   bash tests/static-checks.sh        (run from the project folder; build.sh runs it after compiling)
cd "$(dirname "$0")/.."
APP_SRC="Sources/Core.swift Sources/App.swift Sources/Simple.swift Sources/MailAdapter.swift Sources/Glyph.swift"   # the app itself (SelfTest.swift only makes synthetic fixtures)
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
sheets=$(( $(code Sources/Simple.swift | grep -c 'beginSheet\|NSPopover\|runModal') + $(code "$APP_SRC" | grep -c 'runModal() == .OK, let copy') ))      # the copy path (the simple view) has no sheet or dialog; the dashboard's one sheet is the Mail question (C10)
reads=$(code "$APP_SRC" | grep -E -c 'string\(forType|readObjects|pasteboardItems|data\(forType|changeCount')
check C03 "$([ "$pb" = 1 ] && [ "$inside" = 1 ] && [ "$guarded" = 2 ] && [ "$wired" = 1 ] && [ "$calls" = 2 ] && [ "$onlyWhenOff" = 1 ] && [ "$keyEq" = 0 ] && [ "$returnCopies" = 0 ] && [ "$sheets" = 0 ] && [ "$reads" = 0 ] && echo ok)" "one clipboard path: the Copy button on the simple screen is the only place the clipboard is written, with exactly the text the inline preview shows, and only while that button is enabled; Return in the field never copies, the button has no key shortcut, there is no second sheet, and the clipboard is never read" "NSPasteboard=$pb inside=$inside guarded=$guarded wired=$wired calls=$calls keyEq=$keyEq returnCopies=$returnCopies sheets=$sheets reads=$reads"

proc=$(code "$APP_SRC" | grep -E -c 'Process\(\)|NSTask|posix_spawn|system\(|popen\(|execv|NSWorkspace\.shared\.open|openApplication|launchApplication')
fixed=$(code Sources/Core.swift | grep -E -c 'p\.executableURL = url$|p\.arguments = \[\]$')
calls=$(code Sources/App.swift | grep -c 'RefreshTool\.run(')
order=$(awk '/@objc private func runTool\(\)/,/^    }/' Sources/App.swift | grep -n -E 'let tool = places\.refreshTool|guard confirm\.runModal\(\) == \.alertSecondButtonReturn|RefreshTool\.run\(tool\)' | cut -d: -f1 | tr '\n' ' ')
sorted=$(echo $order | tr ' ' '\n' | sort -n | tr '\n' ' ')
procCore=$(code Sources/Core.swift | grep -c 'Process()'); procMail=$(code Sources/MailAdapter.swift | grep -c 'Process()')
helperPath=$(code Sources/MailAdapter.swift | grep -c 'static let helper = "/usr/bin/osascript"')
helperFixed=$(awk '/static func osascript\(_ source: String, timeout: TimeInterval\)/,/^    }/' Sources/MailAdapter.swift | grep -E -c 'p\.executableURL = URL\(fileURLWithPath: helper\)$|p\.arguments = \["-"\]$|p\.environment = \["PATH": "/usr/bin:/bin"\]$')
helperCalls=$(code "$APP_SRC" | grep -c 'osascript(')
helperFrom=$(code Sources/MailAdapter.swift | grep -c 'static func liveRun(_ source: String) -> (reply: String?, error: Int) { osascript(source, timeout: helperTimeout) }')
check C04 "$([ "$proc" = 2 ] && [ "$procCore" = 1 ] && [ "$procMail" = 1 ] && [ "$fixed" = 2 ] && [ "$calls" = 1 ] && [ "$(echo $order | wc -w | tr -d ' ')" = 3 ] && [ "$order" = "$sorted" ] && [ "$helperPath" = 1 ] && [ "$helperFixed" = 3 ] && [ "$helperCalls" = 2 ] && [ "$helperFrom" = 1 ] && echo ok)" "two programs can be started, each in one place and at a fixed path: ~/WorkIndex/horizon-tools/refresh.command, with no arguments, only from the \"Refresh Feeds…\" action after its confirmation; and (new in 0.5.3) the system's script runner /usr/bin/osascript, with the argument \"-\" and a fixed environment, given the fixed Mail script on its standard input and called only from the Mail step (C10) — it replaces running that script inside the app, which blocked the window. Nothing else is opened or launched" "Process=$proc core=$procCore mail=$procMail fixed=$fixed calls=$calls order=$order helper=$helperPath/$helperFixed/$helperCalls/$helperFrom"

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

ui=0; for s in 'withTitle: "Open Work Context"' 'labels: ["3 months", "6 months", "Custom"]' 'NSButton(title: "Read Sources"' 'NSButton(title: "Import…"' '"Evidence — '; do grep -qF "$s" Sources/App.swift && ui=$((ui+1)); done
for s in 'label("What do you want to continue?"' 'NSButton(title: "Copy"' 'NSButton(title: "Sources & Settings"'; do grep -qF "$s" Sources/Simple.swift && ui=$((ui+1)); done
id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Info.plist 2>/dev/null)
check C08 "$([ "$ui" = 8 ] && [ "$id" = "local.workindex.horizon" ] && echo ok)" "the English interface is there as real controls (Open Work Context, 3 months / 6 months / Custom, Read Sources, Import…, Evidence; What do you want to continue?, Copy, Sources & Settings) and the bundle ID is local.workindex.horizon" "ui=$ui id=$id"

auto=$(code "Sources/App.swift Sources/Simple.swift" | grep -E -c 'Timer|DispatchSourceTimer|NSBackgroundActivityScheduler|asyncAfter|FSEvent|DispatchSource\.makeFileSystemObjectSource|NSMetadataQuery')
check C09 "$([ "$auto" = 0 ] && echo ok)" "nothing runs on a timer, in the background or on a file watcher: sources are read when a window first opens and on \"Read Sources\"" "$auto"

as=$(code "$APP_SRC" | grep -c 'NSAppleScript')
opensApp=$(code "$APP_SRC" | grep -E -c 'launchApplication|openApplication|NSWorkspace\.shared\.launch|\.activate\(options|open -a')
gate=$(awk '/static func collect\(isRunning/,/^    }/' Sources/MailAdapter.swift | grep -n -E 'guard isRunning\(\) else|let allowed = permission\(\)|guard allowed == 0 else|run\(script\(cap: cap\)\)' | cut -d: -f1 | tr '\n' ' ')
gateSorted=$(echo $gate | tr ' ' '\n' | sort -n | tr '\n' ' ')
mailCalls=$(code Sources/App.swift | grep -c 'MailAdapter.collect(')
switchesFirst=$(awk '/static func step\(enabled/,/^    }/' Sources/MailAdapter.swift | grep -n -E 'guard Snapshot.readsImports\(enabled\) else|guard isRunning\(\) else' | cut -d: -f2- | head -1 | grep -c 'guard Snapshot.readsImports(enabled) else')
explicit=$(code Sources/App.swift | grep -c '#selector(readSources(_:))'); viaStep=$(awk '/@objc private func readSources/,/^    }/' Sources/App.swift | grep -c 'switch MailAdapter.step(enabled: preferences.enabled, underway: collecting, isRunning: mailSide.isRunning) {\|case .ask: askAboutMail()')
asks=$(code Sources/App.swift | grep -c 'askAboutMail()'); answers=$(code Sources/App.swift | grep -c 'mailAnswered(collect:')
sheet=$(awk '/private func askAboutMail\(\)/,/^    }/' Sources/App.swift | grep -c 'sheet.beginSheetModal(for: window) {'); modalMail=$(awk '/private func askAboutMail\(\)/,/^    }/' Sources/App.swift | grep -c 'runModal')
mailOrder=$(awk '/private func mailAnswered\(collect: Bool\)/,/^    }/' Sources/App.swift | grep -n -E 'guard collect else|DispatchQueue\.global\(qos: \.userInitiated\)\.async \{$|MailAdapter\.collect\(isRunning: side\.isRunning, permission: side\.permission, run: side\.run\)|guard MailAdapter\.mayKeep\(self\.preferences\.enabled\) else|Importer\.save\(parsed, name: "mac-mail"' | cut -d: -f1 | tr '\n' ' ')
mailSorted=$(echo $mailOrder | tr ' ' '\n' | sort -n | tr '\n' ' ')
offMain=$(awk '/private func mailAnswered\(collect: Bool\)/,/^    }/' Sources/App.swift | grep -A1 'DispatchQueue.global(qos: .userInitiated).async {$' | grep -c 'MailAdapter.collect(')
notOnMain=$(code Sources/MailAdapter.swift | grep -c 'guard !Thread.isMainThread else { return (nil, refusedOnMainThread) }')
selfGuard=$(code Sources/MailAdapter.swift | grep -c 'is not running then error number -600')
passive=$(code Sources/App.swift | grep -c 'readSources(nil)'); oldButton=$(code "$APP_SRC" | grep -c 'collectFromMail\|"Collect from Mail…"\|"Reread Sources"')
check C10 "$([ "$as" = 0 ] && [ "$opensApp" = 0 ] && [ "$(echo $gate | wc -w | tr -d ' ')" = 5 ] && [ "$gate" = "$gateSorted" ] && [ "$mailCalls" = 1 ] && [ "$switchesFirst" = 1 ] && [ "$explicit" = 1 ] && [ "$viaStep" = 2 ] && [ "$asks" = 2 ] && [ "$answers" = 2 ] && [ "$sheet" = 1 ] && [ "$modalMail" = 0 ] && [ "$(echo $mailOrder | wc -w | tr -d ' ')" = 6 ] && [ "$mailOrder" = "$mailSorted" ] && [ "$offMain" = 1 ] && [ "$notOnMain" = 1 ] && [ "$selfGuard" = 1 ] && [ "$passive" = 1 ] && [ "$oldButton" = 0 ] && echo ok)" "Mail can be reached in one way only: the \"Read Sources\" button (its selector; the one other caller is the test hook) → the switches are checked before anything of Mail, then whether Mail is running → a sheet on the window (never a blocking dialog) → only its second button goes on → the collection runs off the main thread (is Mail running, does macOS allow it, the fixed script) → the switches are checked again before anything is saved. The script is not run inside the app any more (no NSAppleScript): the helper refuses on the main thread, and the script itself stops when Mail is not running. No code starts or activates another app, and the two old buttons are gone" "NSAppleScript=$as opensApp=$opensApp gate=$gate calls=$mailCalls switchesFirst=$switchesFirst explicit=$explicit viaStep=$viaStep asks=$asks answers=$answers sheet=$sheet modal=$modalMail order=$mailOrder offMain=$offMain notOnMain=$notOnMain selfGuard=$selfGuard passive=$passive old=$oldButton"

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
hangulCore=$(LC_ALL=en_US.UTF-8 grep '[가-힣]' Sources/Core.swift | grep -v -E '^ +"기타", |datePattern = |"sunday", "회의"|\(re\|fw\|fwd\|답장\|전달\)|s\.contains\("부분"\)|static let filler: Set<String> = \["이어서"|"header", "이메일", "경로", "링크", "헤더"\]|private static let particles = \[|labels\.contains\("보낸"\)|\[\^a-z0-9가-힣\]|\["언제", "며칠", "날짜", "시간"\]\.contains|static let (decision|pending|weakPending|asked)Korean = |^ +"예외", "한도", "상한"|\(re\|fw\|fwd\|aw\|답장\|회신\|전달\)|\(수정\|개정\|버전\|초안\)|차\\s\*\(수정본\|개정본|\(copy\|사본\|복사본\)|#"조건\\s\*:\\s\*\\S"#, #"\\d\[\\d,\.\]\*' | wc -l | tr -d ' ')
compat=$(LC_ALL=en_US.UTF-8 grep -c -E 's\.contains\("부분"\)|labels\.contains\("보낸"\)|private static let particles = \["으로"|"스냅샷", "가져온 자료"|"이메일", "경로", "링크", "헤더"' Sources/Core.swift)
private=$(grep -i -c -E 'not for distribution|private local preview|private preview|비공개' Sources/Core.swift Sources/App.swift Sources/Simple.swift Sources/MailAdapter.swift Info.plist build.sh | awk -F: '{s+=$NF} END {print s+0}')
ver=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist 2>/dev/null); build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist 2>/dev/null); region=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDevelopmentRegion' Info.plist 2>/dev/null)
usage=$(/usr/libexec/PlistBuddy -c 'Print :NSAppleEventsUsageDescription' Info.plist 2>/dev/null | grep -c 'only when you press “Read Sources”, answer its question with “Collect from Mail”')
check C14 "$([ "$hangulUI" = 0 ] && [ "$hangulCore" = 0 ] && [ "$compat" = 5 ] && [ "$private" = 0 ] && [ "$ver" = "0.5.4" ] && [ "$build" = 11 ] && [ "$region" = "en" ] && [ "$usage" = 1 ] && echo ok)" "public English build: no Korean text in the windows, menu, Mail messages, Info.plist or build script; the only Korean left in Core.swift is data the app must still understand (existing labels, search fillers and particles, a localized Gmail label, the \"부분\" coverage note, and the Korean marks of replies, revisions, decisions, limits, pending states and "when" questions used to choose and lay out lines); no private or not-for-distribution wording; version 0.5.4 (11), English development region, and the Mail permission text names the button and the answer that lead to Mail" "hangulUI=$hangulUI hangulCore=$hangulCore compat=$compat private=$private ver=$ver build=$build region=$region usage=$usage"

# The example mailbox: made-up data only, and a generator that touches nothing but its own output file.
S="Examples/sample-mail.mbox"
msgs=$(grep -c '^From sample@example.com ' "$S" 2>/dev/null); subj=$(grep -c '^Subject: ' "$S" 2>/dev/null); ids=$(grep -c '^Message-ID: <sample-[0-9][0-9]-[0-9]\{8\}@example.com>$' "$S" 2>/dev/null)
foreign=$(grep -o -E '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+' "$S" 2>/dev/null | grep -v -c '@example\.com$')
other=$(grep -v -E '^(From sample@example\.com |X-Gmail-Labels: (Inbox|Sent)$|From: [A-Z][a-z]+ Example <[a-z]+@example\.com>$|To: [A-Z][a-z]+ Example <[a-z]+@example\.com>$|Subject: |Date: |Message-ID: |This is a made-up message for trying Contexta Horizon\. It describes no real person, company or event\.$|$)' "$S" 2>/dev/null | wc -l | tr -d ' ')
gen=$(sed -E 's:^ *#.*$::' Examples/make-sample.sh | grep -E -c 'curl|wget|https?://|osascript|sudo|\$HOME|~/|defaults |security |mdfind|find /|rm -r')
check C15 "$([ "${msgs:-0}" -ge 8 ] && [ "$msgs" = "$subj" ] && [ "$msgs" = "$ids" ] && [ "$foreign" = 0 ] && [ "$other" = 0 ] && [ "$gen" = 0 ] && [ -f Examples/README.txt ] && echo ok)" "the example mailbox is made-up data only: every message has a subject and its own id, every address is at example.com, there is no line beyond the known headers and one fixed body sentence; its generator reads nothing from this Mac, uses no network and writes only its output file" "messages=$msgs subjects=$subj ids=$ids foreign=$foreign other=$other generator=$gen"

# The headless lookup (--aside-lookup): answered before AppKit, read-only, stdin in and stdout out.
A=$(code Sources/Core.swift | awk '/^enum AsideLookup/,/^}/')
firstInMain=$(awk '/static func main\(\)/{f=1;next} f&&NF{print;exit}' Sources/App.swift | sed -E 's://.*$::; s/ +$//' | grep -c '^        if CommandLine.arguments.contains("--aside-lookup") { exit(AsideLookup.run()) }$')
coreImports=$(grep -E '^import ' Sources/Core.swift | tr '\n' ' ')
sideEffects=$(echo "$A" | grep -E -c 'store\.set|\.set\(|setCustom|usesCustom *=|months *=|Importer\.|RefreshTool\.|MailAdapter|Process|NSPasteboard|NSApp|standardError|print\(|NSLog|CommandLine|ProcessInfo|createDirectory|\.write\(to')
outWrites=$(echo "$A" | grep -c 'FileHandle.standardOutput.write(')
limit=$(echo "$A" | grep -c 'static let maxInputBytes = 8 \* 1024')
bounded=$(echo "$A" | grep -c 'input.readData(ofLength: maxInputBytes + 1 - data.count)')
sameSettings=$(echo "$A" | grep -c 'answer(input: readInput(), places: Places.standard(), preferences: Preferences(store: DefaultsStore()))')
sameText=$(echo "$A" | grep -c 'return Export.simple(task: task, topic: top, window: view.window, coverage: view.coverage)')
tip=$(grep -c 'copyButton.toolTip = ".*ChatGPT, Claude and Aside' Sources/Simple.swift)
check C16 "$([ "$firstInMain" = 1 ] && [ "$coreImports" = "import Foundation " ] && [ "$sideEffects" = 0 ] && [ "$outWrites" = 1 ] && [ "$limit" = 1 ] && [ "$bounded" = 1 ] && [ "$sameSettings" = 1 ] && [ "$sameText" = 1 ] && [ "$tip" = 1 ] && echo ok)" "the headless lookup is the first thing main() checks, before any AppKit object exists, and lives in the Foundation-only core: it reads standard input up to one byte past 8 KiB, uses the same saved settings and the same Export.simple as the windows, writes one thing (its answer, to standard output) and has no code that changes a setting, imports, runs a tool, asks Mail, starts a process, touches the clipboard, logs, or reads the query from the command line; the Copy tooltip says the text works in ChatGPT, Claude and Aside" "first=$firstInMain imports=$coreImports sideEffects=$sideEffects out=$outWrites limit=$limit bounded=$bounded settings=$sameSettings text=$sameText tip=$tip"

# 0.5.2 — the switches decide what is opened, at the reader.
R=$(code Sources/Core.swift | awk '/^enum Reader/,/^}/'); SN=$(code Sources/Core.swift | awk '/^struct Snapshot/,/^}/'); AL=$(code Sources/Core.swift | awk '/^enum AsideLookup/,/^}/')
readCalls=$(code "$APP_SRC" | grep -c 'Snapshot\.read(')
gatedCalls=$(code "$APP_SRC" | grep -c 'Snapshot\.read(places, enabled: enabled')
feedGate=$(echo "$SN" | grep -c 'func feed(_ kind: SourceKind, _ read: () -> Reader.Loaded) -> Reader.Loaded { enabled.contains(kind) ? read() : off }')
feedsUse=$(echo "$SN" | grep -c 'let \(files\|ai\|mail\) = feed(\.\(files\|ai\|mail\)) { Reader\.load(places\.')
bareLoads=$(echo "$SN" | grep 'Reader\.load(' | grep -v -c 'feed(\.')
manifestGate=$(echo "$SN" | grep -c 'if !enabled.isDisjoint(with: \[.files, .ai, .mail\]) { s.manifest = Manifest.read(places.manifest) }')
manifestReads=$(code "$APP_SRC" | grep -c 'Manifest\.read(')
importsGate=$(echo "$SN" | grep -c 'let imports = Snapshot.readsImports(enabled) ? Reader.imports(places) : (loaded: off, files: 0)')
importsRule=$(echo "$SN" | grep -c 'static func readsImports(_ enabled: Set<SourceKind>) -> Bool { enabled.isSuperset(of: \[.imports, .ai, .mail\]) }')
importsFlat=$(echo "$SN" | grep -c 's.evidence = evidence.filter { $0.isOn(enabled) && ($0.origin != .imports || keepImports) }')
allOffFirst=$(echo "$AL" | grep -n 'if enabled.isEmpty {\|Snapshot\.read(' | cut -d: -f2- | head -1 | grep -c 'if enabled.isEmpty {')
dispatch=$(echo "$R" | grep -c 'probe?("file", url.path)\|probe?("folder", places.imports.path)')
lstats=$(echo "$R" | grep -c 'lstat(url.path, &st)'); opens=$(echo "$R" | grep -c 'FileHandle(forReadingAtPath: url.path)'); lists=$(echo "$R" | grep -c 'contentsOfDirectory(atPath: places.imports.path)'); exists=$(echo "$R" | grep -c 'fileExists(atPath: places.imports.path')
probeSet=$(code "$APP_SRC" | grep -c 'Reader\.probe *=\|\.probe *= ')
stale=$(code Sources/App.swift | grep -c 'guard request == self.reads else { self.staleReads += 1; return }')
cutOnAnswer=$(code Sources/App.swift | grep -c 'self.snapshot = snap.restricted(to: self.preferences.enabled)')
cutOnToggle=$(awk '/@objc private func sourceToggled/,/^    }/' Sources/App.swift | grep -c 'snapshot = snapshot?.restricted(to: enabled)')
readOnToggle=$(awk '/@objc private func sourceToggled/,/^    }/' Sources/App.swift | grep -c 'if let have = have, !enabled.isSubset(of: have) { reread(nil) } else { recompute() }')
check C17 "$([ "$readCalls" = 2 ] && [ "$gatedCalls" = 2 ] && [ "$feedGate" = 1 ] && [ "$feedsUse" = 3 ] && [ "$bareLoads" = 0 ] && [ "$manifestGate" = 1 ] && [ "$manifestReads" = 1 ] && [ "$importsGate" = 1 ] && [ "$importsRule" = 1 ] && [ "$importsFlat" = 1 ] && [ "$allOffFirst" = 1 ] && [ "$dispatch" = 2 ] && [ "$lstats" = 1 ] && [ "$opens" = 1 ] && [ "$lists" = 1 ] && [ "$exists" = 1 ] && [ "$probeSet" = 0 ] && [ "$stale" = 1 ] && [ "$cutOnAnswer" = 1 ] && [ "$cutOnToggle" = 1 ] && [ "$readOnToggle" = 1 ] && echo ok)" "the switches gate reading itself: the dashboard and the lookup command are the only two callers of Snapshot.read and both pass the switches; inside it each feed is read only through its own switch, the manifest only while a feed is on, the imports only while Imports, AI chats and Mail are all on (and a snapshot cut down by a switch drops imports from its flat list too); the lookup answers \"all off\" before reading; the reader has one lstat, one open and one folder listing, each behind the test probe, which nothing in the app sets; the dashboard drops a stale read's answer, cuts every answer down to the current switches, empties memory on switching off and reads on switching on" "reads=$readCalls gated=$gatedCalls feedGate=$feedGate feeds=$feedsUse bare=$bareLoads manifest=$manifestGate/$manifestReads imports=$importsGate/$importsRule/$importsFlat allOffFirst=$allOffFirst dispatch=$dispatch lstat=$lstats open=$opens list=$lists exists=$exists probeSet=$probeSet stale=$stale cut=$cutOnAnswer/$cutOnToggle readOnToggle=$readOnToggle"

# 0.5.2 — the fictional example lives only in the simple window.
FX=$(awk '/^struct FictionalExample/,/^}/' Sources/Simple.swift)
elsewhere=$(grep -c -i 'FictionalExample\|fictional' Sources/Core.swift Sources/App.swift Sources/MailAdapter.swift | awk -F: '{s+=$NF} END {print s+0}')
fxReach=$(echo "$FX" | sed -E 's://.*$::' | grep -E -c 'FileManager|UserDefaults|DefaultsStore|NSPasteboard|Snapshot|Places|Importer|Reader|preferences|Preferences|\.write|FileHandle|URL\(|Process|dashboard')
fxMade=$(echo "$FX" | grep -c 'return FictionalExample(topics: Analysis.topics(evidence, window: window, enabled: Set(SourceKind.allCases)), window: window)')
noCopy=$(awk '/@objc private func copyShown\(\)/,/^    }/' Sources/Simple.swift | grep -n 'guard example == nil else { return }\|NSPasteboard.general' | head -1 | grep -c 'guard example == nil else { return }')
copyOff=$(code Sources/Simple.swift | grep -c 'copyButton.isEnabled = !shownText.isEmpty && example == nil')
offer=$(code Sources/Simple.swift | grep -c 'exampleOffer.isHidden = !(example == nil && !loading && dashboard.isLoaded && dashboard.currentTopics.isEmpty && query.isEmpty)')
enter=$(code Sources/Simple.swift | grep -c 'guard example == nil, !loading, dashboard.isLoaded, dashboard.currentTopics.isEmpty, field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }')
makes=$(code Sources/Simple.swift | grep -c 'FictionalExample.make()')
sameFormatter=$(code Sources/Simple.swift | grep -c 'Export.simple(task: query, topic: $0, window: example?.window ?? dashboard.currentWindow, coverage: example == nil ? dashboard.currentCoverage : \[\])')
labels=0; for t in 'NSButton(title: "Try a fictional example"' 'NSButton(title: "Exit example"' '"Fictional example — made-up Harborline records. Nothing here is from your Mac, and nothing is saved or copied."' '"Contexta Horizon — fictional example"'; do grep -qF "$t" Sources/Simple.swift && labels=$((labels+1)); done
check C18 "$([ "$elsewhere" = 0 ] && [ "$fxReach" = 0 ] && [ "$fxMade" = 1 ] && [ "$noCopy" = 1 ] && [ "$copyOff" = 1 ] && [ "$offer" = 1 ] && [ "$enter" = 1 ] && [ "$makes" = 1 ] && [ "$sameFormatter" = 1 ] && [ "$labels" = 4 ] && echo ok)" "the fictional example exists only in the simple window: the core, the dashboard and the Mail adapter do not mention it (so the lookup command cannot return it); it is built from fixed made-up titles with no file, settings, clipboard, source or dashboard access; it is made in one place, when its button is pressed, and only on the empty screen with nothing typed; its preview comes from the same Export.simple call as a real one; the Copy action returns before the clipboard when the example is on and the button is off; and it is labelled in the button, the banner and the window title" "elsewhere=$elsewhere reach=$fxReach made=$fxMade noCopy=$noCopy copyOff=$copyOff offer=$offer enter=$enter makes=$makes formatter=$sameFormatter labels=$labels"

# 0.5.3 — windows open at once and stay usable; the icon is the continued-thread mark.
noDouble=$(code Sources/App.swift | grep -c 'func ensureLoaded() { if snapshot == nil && !busy { reread(nil) } }')
joins=$(awk '/@objc private func readSources/,/^    }/' Sources/App.swift | grep -c 'if busy, let underway = readingFor, preferences.enabled.isSubset(of: underway) { joinedPresses += 1 } else { reread(nil) }')
clears=$(awk '/^    private func recompute\(\) \{/,/^    }/' Sources/App.swift | grep -c 'topics = \[\]; coverages = \[\]; selected = nil')
limit=$(code Sources/App.swift | grep -c 'var inlineLimit = 400$')
showUses=$(awk '/^    func show\(\) \{/,/^    }/' Sources/App.swift | grep -c 'ensureLoaded()'); showReads=$(awk '/^    func show\(\) \{/,/^    }/' Sources/App.swift | grep -c 'reread(')
frontFirst=$(awk '/func show\(pick: String\? = nil\)/,/^    }/' Sources/Simple.swift | grep -n 'window.makeKeyAndOrderFront(nil)\|dashboard.ensureLoaded()' | cut -d: -f2- | head -1 | grep -c 'makeKeyAndOrderFront')
topicsOnce=$(code Sources/App.swift | grep -c 'Analysis\.topics('); topicsIn=$(awk '/private static func compute\(_ snap: Snapshot/,/^    }/' Sources/App.swift | grep -c 'Analysis.topics(snap.evidence, window: resolved.window, enabled: enabled)')
staleCompute=$(code Sources/App.swift | grep -c 'guard request == self.computes else { self.staleComputes += 1; return }')
inline=$(code Sources/App.swift | grep -c 'if snap.evidence.count <= inlineLimit { computing = false; apply(HorizonController.compute(snap, resolved, enabled)); return }')
readOffMain=$(awk '/@objc func reread\(_ sender: Any\?\)/,/^    }/' Sources/App.swift | grep -A2 'DispatchQueue.global(qos: .userInitiated).async {$' | grep -c 'let snap = Snapshot.read(places, enabled: enabled)')
loadingSaid=$(code Sources/Simple.swift | grep -c 'loading = example == nil && (!dashboard.isLoaded || (dashboard.isComputing && topics.isEmpty))')
spinners=$(( $(code Sources/App.swift | grep -c 'spinner.startAnimation(nil)') + $(code Sources/Simple.swift | grep -c 'spinner.startAnimation(nil)') ))
glyphUsed=$(code Sources/App.swift | grep -c 'button.image = ThreadGlyph.menuImage()'); oldSymbol=$(code "$APP_SRC" | grep -c 'systemSymbolName: "calendar\|systemSymbolName: "clock\|arrow.clockwise\|arrow.triangle.2.circlepath')
template=$(code Sources/Glyph.swift | grep -c 'image.isTemplate = true'); oneGeometry=$(grep -c 'ThreadGlyph\.' Icon/make-icon.swift)
iconKey=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' Info.plist 2>/dev/null)
ICNS="dist/contexta-horizon.app/Contents/Resources/AppIcon.icns"; reps=0
if [ -f "$ICNS" ]; then rm -rf dist/icon-build/check.iconset; mkdir -p dist/icon-build; iconutil -c iconset "$ICNS" -o dist/icon-build/check.iconset 2>/dev/null && reps=$(ls dist/icon-build/check.iconset | grep -c '\.png$'); fi
sameIcns=$(cmp -s "$ICNS" Icon/AppIcon.icns && echo 1 || echo 0)
# the approved "-C-" mark: one canonical path, stroked 9 wide with round caps and no fill, in a 112 by 80 box
CANON='M6 40H32 M69 20A23 23 0 1 0 69 60 M80 40H106'
canonSource=$(grep -c "static let path = \"$CANON\"" Sources/Glyph.swift); canonBox=$(grep -c 'static let viewBox = CGSize(width: 112, height: 80)' Sources/Glyph.swift); canonStroke=$(grep -c 'static let strokeWidth: CGFloat = 9' Sources/Glyph.swift)
MARK="<path d=\"$CANON\" fill=\"none\" stroke=\"#20231F\" stroke-width=\"9\" stroke-linecap=\"round\"/>"
vector=0; for f in Icon/mark.svg Icon/icon.svg; do grep -qF "$MARK" "$f" 2>/dev/null && vector=$((vector+1)); done
grep -qF "<path d=\"$CANON\" fill=\"none\" stroke=\"#000000\" stroke-width=\"9\" stroke-linecap=\"round\"/>" Icon/menu-glyph.svg 2>/dev/null && vector=$((vector+1))
markBox=$(grep -c '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 112 80" width="112" height="80">' Icon/mark.svg 2>/dev/null)
tile=0; for t in '<g transform="translate(100 100) scale(7.357142857)">' '<rect width="112" height="112" rx="25" fill="#F4D447"/>' '<svg x="12.5" y="20" width="87" height="72" viewBox="0 0 112 80" preserveAspectRatio="xMidYMid meet">'; do grep -qF "$t" Icon/icon.svg 2>/dev/null && tile=$((tile+1)); done
menuFit=$(grep -cF '<svg x="0" y="0" width="18" height="18" viewBox="0 0 112 80" preserveAspectRatio="xMidYMid meet">' Icon/menu-glyph.svg 2>/dev/null)
flat=$(( $(grep -c -i 'gradient\|shadow\|opacity\|filter' Icon/icon.svg Icon/mark.svg 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}') + $(sed -E 's://.*$::' Icon/make-icon.swift | awk '/static func appIcon/,/^    }/' | grep -c -i 'gradient\|shadow\|setAlpha\|strokePath\|setLineWidth') ))
samePath=$(sed -E 's://.*$::' Icon/make-icon.swift Sources/Glyph.swift | grep -c 'M6 40\|A23 23\|H106')            # the path is written once, in Glyph.swift; everything else asks for it
menuPng=$([ -s Icon/menu-glyph.png ] && [ -s "Icon/menu-glyph@2x.png" ] && echo 1 || echo 0)
clockish=$(grep -c -i '<circle\|<polygon\|clock\|calendar' Icon/icon.svg Icon/mark.svg Icon/menu-glyph.svg 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}'); previewPng=$([ -s Icon/icon-preview.png ] && echo 1 || echo 0)
check C19 "$([ "$noDouble" = 1 ] && [ "$joins" = 1 ] && [ "$clears" = 1 ] && [ "$limit" = 1 ] && [ "$showUses" = 1 ] && [ "$showReads" = 0 ] && [ "$frontFirst" = 1 ] && [ "$topicsOnce" = 1 ] && [ "$topicsIn" = 1 ] && [ "$staleCompute" = 1 ] && [ "$inline" = 1 ] && [ "$readOffMain" = 1 ] && [ "$loadingSaid" = 1 ] && [ "$spinners" = 2 ] && [ "$glyphUsed" = 1 ] && [ "$oldSymbol" = 0 ] && [ "$template" = 1 ] && [ "$oneGeometry" -ge 4 ] && [ "$iconKey" = "AppIcon" ] && [ "$reps" = 10 ] && [ "$sameIcns" = 1 ] && [ "$canonSource" = 1 ] && [ "$canonBox" = 1 ] && [ "$canonStroke" = 1 ] && [ "$vector" = 3 ] && [ "$markBox" = 1 ] && [ "$tile" = 3 ] && [ "$menuFit" = 1 ] && [ "$flat" = 0 ] && [ "$samePath" = 1 ] && [ "$menuPng" = 1 ] && [ "$clockish" = 0 ] && [ "$previewPng" = 1 ] && echo ok)" "windows first, work after: a window is put on screen before a read is asked for, a read already under way is not asked for again on reopening or by pressing \"Read Sources\" again, a slow recomputation first clears the old topics, coverage and selection (so nothing a switch or period now excludes stays on screen), only snapshots of up to 400 records are worked out on the main thread, files are read and (for large snapshots) topics worked out off the main thread with stale results dropped, and both windows have a spinner and say \"reading\" rather than \"empty\"; the icon is the approved \"-C-\" mark from one canonical path (M6 40H32 M69 20A23 23 0 1 0 69 60 M80 40H106 in a 112 by 80 box, stroke 9, round caps, no fill), written once in Glyph.swift — a template glyph in the menu bar, the same path scaled in proportion and centred in 18 points (no clock, calendar or refresh symbol); and a Finder icon that is the 112 tile (corner radius 25, the mark as an 87 by 72 box centred, flat Index Yellow #F4D447 with the mark in #20231F, no gradient, shadow or transparency) inside the macOS margins — as a ten-size AppIcon.icns in the built bundle, named by the plist, identical to the one made from source, with its SVG files, menu PNGs and preview" "noDouble=$noDouble joins=$joins clears=$clears limit=$limit show=$showUses/$showReads frontFirst=$frontFirst topics=$topicsOnce/$topicsIn staleCompute=$staleCompute inline=$inline readOffMain=$readOffMain loading=$loadingSaid spinners=$spinners glyph=$glyphUsed old=$oldSymbol template=$template geometry=$oneGeometry key=$iconKey reps=$reps same=$sameIcns canon=$canonSource/$canonBox/$canonStroke vector=$vector markBox=$markBox tile=$tile menuFit=$menuFit flat=$flat samePath=$samePath menuPng=$menuPng clockish=$clockish preview=$previewPng"

echo
echo "== $pass/$((pass+fail)) static checks passed =="
[ "$fail" = 0 ]
