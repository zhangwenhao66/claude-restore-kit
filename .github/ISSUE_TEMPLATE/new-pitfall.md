---
name: A problem the docs don't cover
about: You hit something during a restore that this kit should warn about
title: "[pitfall] "
labels: ["documentation", "needs-triage"]
---

<!-- This is the most useful kind of report. -->

## The problem

<!-- one or two sentences -->

## Why it is not obvious

<!-- What makes it hard to spot? Did it look like a different problem? Was it intermittent?
     Did a config look correct while the behaviour was wrong? -->

## How it showed up

```
```

## The fix / workaround

<!-- what you did, and whether it is a permanent fix or a workaround -->

## Which direction does it apply to?

- [ ] only when coming BACK from a gateway (this kit's direction)
- [ ] any account/deployment change (probably belongs in the sibling kit too)
- [ ] unrelated to the restore (but hit during one)

## Checklist

- [ ] I removed account UUIDs, gateway URLs, tokens and personal paths
- [ ] I checked it is not already in `docs/05-pitfalls.md`
