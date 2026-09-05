<!--
SPDX-FileCopyrightText: 2026 KDE Agents Usage contributors
SPDX-License-Identifier: MIT
-->

# Contributing

Contributions to KDE Agents Usage are welcome. You can report problems, improve documentation, add tests, or support more quota sources.

## Protect private data

Git commits and pull requests are public records. Configure a GitHub private email before you create commits.

Use synthetic data in tests and examples. Do not submit real names, email addresses, tokens, account identifiers, prompts, responses, or session logs.

Remove unrelated log lines before you submit a bug report. Use GitHub private vulnerability reporting for sensitive security details.

## Publish a release

The [release workflow](.github/workflows/release.yml) builds and publishes the plasmoid package. Create a tag to start it:

```bash
git tag v0.1.1 && git push origin v0.1.1
```

The workflow runs the tests, sets the version in `metadata.json` from the tag, and attaches `io.github.kde-agents-usage-<version>.plasmoid` to a GitHub release. Do not edit `metadata.json` for a release.

To install a release file locally, run:

```bash
kpackagetool6 --type Plasma/Applet --upgrade <file>.plasmoid
```

## Submit a change

1. Fork the repository.
2. Create a branch for one change.
3. Add or update tests for behavior changes.
4. Run the test commands from [README.md](README.md).
5. Examine the staged diff for private data.
6. Open a pull request with a clear description.

Keep changes small when possible. Keep the widget compatible with KDE Plasma 6 and Python 3.10 or newer.

All contributions use the [MIT License](LICENSE).
