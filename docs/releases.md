# Private release process

A repository version identifies a compatible set of skills, instruction
fragments, schemas, and helper scripts. The repository does not publish an npm
package.

## Prepare a version

1. Confirm that each user-visible pull request includes a changeset.
2. Run `npm ci` and `npm test` on a clean checkout.
3. Let the **Version packages** workflow open or update the version pull
   request after changesets reach `main`.
4. Review the version and changelog changes in that pull request.
5. Merge the reviewed version pull request into `main`.
6. Run the **Private release** workflow with the exact `package.json` version.
   The workflow reruns all checks, verifies the changelog, creates an annotated
   `agent-skills-v<version>` tag, and creates the GitHub release.

Do not make the repository public. Do not publish an npm package. Either action
requires a separate user decision.

The release workflows never run `npm publish`.
