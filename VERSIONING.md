# Versioning & rollout

This repo is a **template**. Every client/app runs it from a **pinned git tag**, never
from a moving branch — so a change here never auto-propagates to every client.

## Release flow

1. Merge changes to `main`.
2. Tag: `git tag v1.4.0 && git push --tags`.
3. Bump one client's workspace to the new tag (the "canary") and apply.
4. Once healthy, roll the tag out to the rest of the fleet.

In Terraform Cloud, set each workspace's **VCS branch/tag** to the pinned tag
(or drive it from the `factory/` definition, which sets `vcs_repo.branch`/tag per workspace).

## Why

A monorepo gives you atomic, reviewable releases; tag-pinning gives you a blast-radius
switch. "A fix reaches everyone" is good; "a mistake reaches everyone" is not — pinning
lets you choose when.
