# Taqasta

![taqasta (1)-min](https://user-images.githubusercontent.com/592009/198849659-e778c37a-29fb-4f4b-a503-9fd1ee32410a.png)

A full-featured MediaWiki stack for easy deployment of enterprise-ready MediaWiki on production environments.

Note: This repo is a fork of the MediaWiki application Docker image included in the Canasta stack.
For complete documentation on the overall Canasta tech stack, including installation instructions,
please visit https://github.com/CanastaWiki/Canasta-Documentation.

# Submitting changes back to Canasta

1. Ensure your local version of repo has `upstream` set to the Canasta repo:

```bash
git remote -v
# if upstream is missing, add it
git remote add upstream git@github.com:CanastaWiki/Canasta.git
```

2. Switch to `origin/canasta` branch

```bash
git fetch origin
git fetch upstream
git checkout canasta
```

3. Update the branch by merging Canasta repo changes into the `canasta` branch

```bash
git merge upstream/master
```

4. Create a new branch for your changes

```bash
git checkout -b fork/name-of-my-change
```

4. Cherry-pick desired change into just created `fork/name-of-my-change` branch

```bash
git cherry-pick <commit-hash>
```

5. Push the `fork/name-of-my-change` branch changes to this repo

```bash
git push origin canasta
```

6. Create PR from this repo back to Canasta repo

https://github.com/WikiTeq/Taqasta/pulls , ensure that you have `CanastaWiki/Canastas:master` choosen as base,
and `WikiTeq/Taqasta:fork/name-of-my-change` as compare.
