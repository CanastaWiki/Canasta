# Security Policy

## Reporting a vulnerability

Please do not report security vulnerabilities through public issues, pull requests, or discussions.

Report them privately through GitHub: open this repository's **Security** tab and choose **Report a vulnerability**. This creates a private advisory visible only to you and the maintainers.

Include what you can of:
- The Canasta version or image tag affected
- Steps to reproduce, or a proof of concept
- The impact you expect

## Supported versions

Security fixes are made to the latest Canasta release. Please confirm the issue on the latest release before reporting.

## Scope

This policy covers the Canasta image:
- The Dockerfile and the image build
- The selection and pinned versions of bundled extensions and skins in `contents.yaml`
- The patches Canasta applies to bundled extensions and skins in `patches/`

Report these elsewhere:
- Vulnerabilities in MediaWiki core or Wikimedia-maintained extensions and skins: https://www.mediawiki.org/wiki/Reporting_security_bugs
- Vulnerabilities in third-party extensions and skins: the extension's or skin's own maintainers
- Vulnerabilities in the base image, its scripts, or its Apache and PHP configuration: https://github.com/CanastaWiki/CanastaBase
- Vulnerabilities in the Canasta CLI: https://github.com/CanastaWiki/Canasta-CLI

If you are unsure where an issue belongs, report it here and we will help route it.
