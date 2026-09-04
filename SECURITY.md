<!--
SPDX-FileCopyrightText: 2026 KDE Agents Usage contributors
SPDX-License-Identifier: MIT
-->

# Security Policy

## Report a vulnerability

Use the **Security** tab and select **Report a vulnerability**. This method keeps the report private until a fix is available.

Do not open a public issue for a vulnerability. Do not include real tokens, credentials, prompts, responses, or session files.

Include the affected version, the impact, and minimal reproduction steps. Use synthetic data in the reproduction.

## Supported version

Security fixes apply to the latest revision on the default branch. Older revisions do not receive separate security updates.

## Security model

The default configuration uses local data sources and makes no network requests.

Optional Anthropic API access requires explicit user consent. The helper sends the OAuth token only to the configured HTTPS endpoint.

The helper does not follow HTTP redirects for this request. Cache files contain normalized quota data and use user-only permissions.
