# Private release process

A repository version identifies a compatible set of skills, instruction
fragments, schemas, and helper scripts. The repository does not publish an npm
package.

## Prepare a version

1. Confirm that each user-visible pull request includes a changeset.
2. Run `npm ci` and `npm test` on a clean checkout.
3. Run `npm run release:version` on a release branch.
4. Review the version and changelog changes.
5. Merge the reviewed release pull request into `main`.
6. Create a private GitHub release from the resulting commit.

Do not make the repository public. Do not publish an npm package. Either action
requires a separate user decision.
