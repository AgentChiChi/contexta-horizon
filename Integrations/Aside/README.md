# Resume your work in Aside

**Optional integration for Contexta Horizon public preview v0.5.4 (build 11).** You can use Horizon with ChatGPT, Claude, or Aside without installing this skill: choose your own records in Horizon, review the preview, click **Copy**, and paste it into the conversation you choose. No provider account connection is required for that flow.

## Install the skill

1. Install [Contexta Horizon v0.5.4](https://github.com/AgentChiChi/contexta-horizon/releases/tag/v0.5.4) at `~/Applications/contexta-horizon.app`. The helper looks in your home Applications folder, not `/Applications`. Follow the [guide's installation and macOS safety steps](../../GUIDE.md#install-or-upgrade). Run `node --version`; if Node.js is missing, install a supported Node.js LTS release.
2. Download [Horizon-Aside-skill.zip](https://github.com/AgentChiChi/contexta-horizon/releases/download/v0.5.4/Horizon-Aside-skill.zip). Compare its SHA-256 with the entry in [SHA256SUMS.txt](https://github.com/AgentChiChi/contexta-horizon/releases/download/v0.5.4/SHA256SUMS.txt) before extracting. Copy the `horizon-resume` folder into `skills/user` in the root of your active Aside account. Keep `SKILL.md` and `scripts/lookup.mjs` together in that folder, with no extra archive folder in between. Open a new Aside chat. To check installation without looking up your records, ask whether `horizon-resume` is available.

You can inspect the [skill rules](horizon-resume/SKILL.md) and [local helper](horizon-resume/scripts/lookup.mjs) before installing.

## Ask about earlier work

Ask **“Where did we leave the Harborline quote?”** No wake word or command is needed. **“Let's revisit that quote”** can work if the current chat points to one clear project. If the answer is already in the chat, Aside uses it instead of looking up records. If your project is unclear, Aside asks which one you mean. A bare **“try again”**, rewriting a visible draft, or a web search doesn't trigger lookup. Say **“Use only this chat”** to rule it out.

The built-in **Try a fictional example** preview is only for the Horizon window: **Copy** is disabled, and Aside can't retrieve it. For a fictional lookup you can share, [import the sample mailbox](../../GUIDE.md#optional-practice-with-a-sample-mailbox) first, or use your own selected records.

## Scope and privacy

The skill sends a short topic query, not the entire conversation, to the local Horizon app. Lookup reads only eligible local sources using Horizon's saved period and source settings. Disabled feeds are not opened. Imports are opened only while **Imports**, **AI chats**, and **Mail** are all on. With every source switch off, there are no source reads and lookup reports unavailable. See [what each source switch does](../../GUIDE.md#what-a-source-switch-does).

Aside lookup never opens Apple Mail or requests Mail collection. It can use eligible saved mail records, including local imports. Only [Read Sources in Horizon](../../GUIDE.md#read-sources-and-optional-mail-collection) can offer live collection, and only if **Imports**, **AI chats**, and **Mail** are all on and Apple Mail is already running. **Local Sources Only** is the default; collection requires explicitly choosing **Collect from Mail**. Live Apple Mail and the real macOS Automation prompt were not verified in build 10.

If there is a match, dated reference text goes into the **current Aside chat** and may be processed by its model. It doesn't copy to the clipboard, send to a separate app, or open original documents. Titles can be sensitive and aren't proof of a decision or completed work. Use Horizon's manual **Copy** flow if you want to review the exact text before sharing it.

## Troubleshooting

Open Simple View from Horizon's `-C-` menu-bar icon and try the same named project. Wait for the loading spinner to finish before checking the result. If the project appears there but Aside doesn't find it, check the home Applications path, Node.js, and the skill path in your active account, then try in a new chat. If lookup is unavailable, check whether an enabled source is readable and nonempty. If there's no match, check the query and selected date range. A lookup doesn't automatically widen its scope.

## For scripts

The app executable can return a single top match without opening a window or writing to the clipboard:

```sh
printf '%s' '{"query":"Follow up on the Harborline quote"}' | \
  "$HOME/Applications/contexta-horizon.app/Contents/MacOS/ContextaHorizon" --aside-lookup
```

Send one UTF-8 JSON object with a single nonempty `query` string on stdin (maximum 8 KiB). Check `schema` for `horizon.aside.v1` and inspect `status`: `matched` returns the same handoff as the top preview in Horizon for that query. `no_match`, `unavailable`, and `invalid` return an empty `handoff`. Don't log the handoff if the titles are sensitive.
