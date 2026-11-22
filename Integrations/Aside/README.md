# Resume your work in Aside

Ask **“Where did we leave the Harborline quote?”** or **“샘플 실증 어디까지 했지?”** You do not need to say Horizon or use a command. With one clear project already in the conversation, **“그 견적 다시 보자”** works too. If the current chat already contains the answer, Aside uses that instead of looking up local records.

**“다시”** alone retries the current task, not the work index. Ordinary questions and web searches are not lookups. Say **“이 대화만 보고 답해”** or **“use only this chat”** to rule out lookup. If it is unclear which previous work item you mean, Aside asks rather than scanning unrelated projects.

This account skill requires Node.js and the Horizon 0.5.1 Mac app at `~/Applications/contexta-horizon.app`. When used, a short topic goes to the local app. Its dated reference titles enter the current Aside chat and may be processed by the chat's model. It does not read source document bodies, write to the clipboard, or send anything to another app. Horizon's date and source settings still apply.

For ChatGPT or Claude, review the preview in Horizon, click **Copy**, and paste it into the chat you choose. No provider account connection is required.

## Install or inspect the integration

[Download the skill ZIP](https://github.com/AgentChiChi/contexta-horizon/releases/download/v0.5.1/Horizon-Aside-skill.zip) and follow the [English installation steps](../../GUIDE.md#optional-let-aside-find-earlier-work). You can inspect the [skill rules](horizon-resume/SKILL.md) and its [local helper](horizon-resume/scripts/lookup.mjs) before installing.

### For scripts

The same executable can return a single top match without opening a window or writing to the clipboard:

```sh
printf '%s' '{"query":"Follow up on the Harborline quote"}' | \
  "$HOME/Applications/contexta-horizon.app/Contents/MacOS/ContextaHorizon" --aside-lookup
```

Input is one JSON object on stdin (maximum 8 KiB). Check `schema: horizon.aside.v1` and `status`: `matched` returns the handoff, `no_match`, `unavailable` and `invalid` return an empty handoff. A matched handoff uses the same dated preview as the app, with the current source and period settings. Do not log it if the titles are sensitive.
