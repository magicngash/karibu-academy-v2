# TODO

- [x] After a learner passes a module, Continue opens the next available module with fresh module-specific state; when there is no available next module, the next-module action is not shown and Back to modules remains available.
- [ ] Temporarily set the server-side and learner-facing assessment pass mark to 20% for end-to-end workflow testing, visibly warn that attempts passing during test mode remain recorded as passed, and restore the server-side and learner-facing pass mark to 80% after the user confirms testing is complete.
- [x] The assessment pass mark is temporarily 20% across all accounts for end-to-end workflow testing, and the signed-in app warns users that this temporary mark applies globally and passes recorded at 20% remain recorded after the normal 80% standard is restored.
- [ ] After the user confirms workflow testing is complete, restore server-side and learner-facing assessment pass marks to 80%; retain test attempts that were recorded as passed while the 20% mark was active.
