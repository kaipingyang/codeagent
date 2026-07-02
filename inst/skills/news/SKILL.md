---
name: news
description: Update NEWS.md with recent changes for R package release
argument-hint: "<version or description of changes>"
allowed-tools:
  - Read
  - Edit
  - Bash
  - Glob
---

Update NEWS.md with recent changes following tidyverse NEWS conventions.

**Format**:
```markdown
# packagename X.Y.Z

* New `foo()` function that does X (#123).
* `bar()` now accepts a `baz` argument for Y.
* Fixed bug where `qux()` returned incorrect results for empty input (#456).
```

**Steps**:
1. Read the current `NEWS.md` to understand the format used
2. Run `git log --oneline` to see recent commits since last release
3. Categorize changes:
   - New features: "New `function()` ..."
   - Bug fixes: "Fixed ..."  
   - Breaking changes: "**BREAKING**: ..."
   - Improvements: "`function()` now ..."
4. Write entries in past tense, reference GitHub issues as `(#N)`
5. Place new entries under a `# packagename (development version)` heading
   or create a new version heading

**Tidyverse NEWS style rules**:
- Bullet points start with backtick-quoted function names when relevant
- Each bullet is one sentence, ends with a period
- Breaking changes go first, new features next, bug fixes last
- Version headings: `# pkgname X.Y.Z` (not `## Version X.Y.Z`)
