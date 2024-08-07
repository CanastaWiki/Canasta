---
name: Community support request
about: Get support from the community for when you are unsure if it is a bug.
title: ''
labels: question
assignees: ''

---

## Describe the situation
**Summary**: A clear, one-sentence summary of what your situation is. _e.g. Varnish guru meditation error continues to appear after 5 minutes of starting up Canasta._

**Description**: Full description of the situation.

**Screenshots**: If applicable, add screenshots to help elucidate your situation.

**Steps to reproduce the issue** (if applicable):
1. Run `canasta ,,,`
2. Add `foo.php` into `config/bar.php`
3. Open wiki to `Main Page`
4. Error appears

## Expected behavior
A clear and concise description of what you expected to happen.

## System info
_Please complete the following information:_
 - MediaWiki version (e.g. 1.39.7)
 - Canasta version
 - Canasta CLI version
 - Installed extensions and versions (e.g. Semantic MediaWiki 4.0.2, Cargo as of 2024-04-20, etc.)
 - Host operating system
 - Do you have sudo/root permissions on the host OS?
 - Any other context you think is appropriate to include here

## Sanity checks
Only applies to troubleshooting requests.

- Have you checked the documentation on canasta.wiki for how to address this? Yes/No
- Have you checked prior issues on GitHub yet? Yes/No
- Are you following all Canasta approaches and have **_avoided_** doing things such as running `docker exec` directly on the container, removing the Caddy/Varnish containers, adding unauthorized files to the Docker container after startup, etc.? Yes/No

If you answered no to any of the above sanity check questions, please do not open this support request until you can answer yes to all of the questions.
