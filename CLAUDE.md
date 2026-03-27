# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Interaction Protocol

These rules govern how Claude behaves before, during, and after any task.

### Before Writing Any Code

- **MUST** describe the approach and wait for explicit approval before writing code.
- **MUST** ask clarifying questions if requirements are ambiguous — do not assume and proceed.
- **MUST** if a task touches > 3 files, stop and break it into smaller subtasks first. Present the breakdown and get approval before starting any of them.
- **MUST** read LEARNING.md at the start of any non-trivial session to calibrate communication style.

### While Coding

- **MUST NOT** jump ahead to the next logical step without confirmation. Do one thing, stop, wait.
- **MUST NOT** refactor, rename, or restructure code that wasn't explicitly asked to change. Touch only what was asked.
- **MUST NOT** make broad "while I'm here" improvements — scope is exactly what was requested.
- When given a paste of code or text, find the gap between what it shows and what is being asked. Do not summarize it back.

### After Writing Code

- **MUST** list what could break as a result of the changes.
- **MUST** suggest specific tests to cover those risks.
- Run existing tests and type checks before declaring work done.

### Bug Workflow

- **MUST** write a failing test that reproduces the bug first, then fix code until the test passes. Never fix first.

### Self-Updating Rules

- **MUST** when the user corrects behavior, add a new rule to this file immediately so it never recurs.
- **MUST NOT** add commands, file structure, or architecture descriptions to CLAUDE.md — Claude explores the codebase directly. Only add things Claude cannot discover on its own (behavior rules, coding standards, shortcuts).

### Communication Style (from LEARNING.md)

- **Bottom line first.** State the answer, then support it. Never build to a conclusion.
- **"wait"** = misalignment caught in real time. Pivot immediately and cleanly. Do not explain why the original answer was still relevant.
- **"so..."** at the start of a message = the user is testing their mental model, not summarizing. Push back if it's slightly off — this is the highest-leverage correction point.
- **Short answers first.** Depth on request only.
- **Intuition before formalism.** If the user asks for "simple" or "intuitive", the formal version didn't land. Give an analogy first.
- **"ohhh ok" / "i see"** = done. Move on immediately.

---

## Implementation Best Practices

### 0 - Purpose

These rules ensure maintainability, safety, and developer velocity.
**MUST** rules are enforced by CI; **SHOULD** rules are strongly recommended.

---

### 1 - Before Coding

- **BP-1 (MUST)** Ask the user clarifying questions.
- **BP-2 (SHOULD)** Draft and confirm an approach for complex work.
- **BP-3 (SHOULD)** If >= 2 approaches exist, list clear pros and cons.

---

### 2 - While Coding

- **C-1 (MUST NOT)** Do not follow TDD for this project. Implement directly without writing tests first.
- **C-2 (MUST)** Name functions with existing domain vocabulary for consistency.
- **C-3 (SHOULD NOT)** Introduce classes when small testable functions suffice.
- **C-4 (SHOULD)** Prefer simple, composable, testable functions.
- **C-5 (MUST)** Use `import type { ... }` for type-only imports.
- **C-6 (SHOULD NOT)** Add comments except for critical caveats; rely on self-explanatory code.
- **C-7 (SHOULD)** Default to `type`; use `interface` only when more readable or interface merging is required.
- **C-8 (SHOULD NOT)** Extract a new function unless it will be reused elsewhere, is the only way to unit-test otherwise untestable logic, or drastically improves readability of an opaque block.

---

### 3 - Testing

- **T-1 (MUST)** For a simple function, colocate unit tests in `*.spec.ts` in same directory as source file.
- **T-2 (MUST)** For any API change, add/extend integration tests in `test/*.spec.ts`.
- **T-3 (MUST)** ALWAYS separate pure-logic unit tests from integration tests.
- **T-4 (SHOULD)** Prefer integration tests over heavy mocking.
- **T-5 (SHOULD)** Unit-test complex algorithms thoroughly.
- **T-6 (SHOULD)** Test the entire structure in one assertion if possible
  ```ts
  expect(result).toEqual([value]) // Good

  expect(result).toHaveLength(1); // Bad
  expect(result[0]).toBe(value);  // Bad
  ```

---

### 4 - Code Organization

- **O-1 (MUST)** Place shared types in the appropriate `types.ts` or `*.schemas.ts` file within each module.
- **O-2 (SHOULD)** Colocate related logic (e.g., `workers.service.ts` with `workers.service.spec.ts`).

---

### 5 - Tooling Gates

- **G-1 (MUST)** TypeScript compilation must pass with no errors before marking work done.
- **G-2 (MUST)** All relevant tests must pass before marking work done.

---

### 6 - Git

- **GH-1 (MUST)** Use Conventional Commits format: https://www.conventionalcommits.org/en/v1.0.0
- **GH-2 (MUST NOT)** Refer to Claude or Anthropic in commit messages.
- **GH-3 (MUST)** Keep commit messages concise. No long bodies unless there's a breaking change explanation.

---

## Writing Functions Best Practices

When evaluating whether a function is good, use this checklist:

1. Can you read the function and HONESTLY easily follow what it's doing? If yes, stop here.
2. Does it have very high cyclomatic complexity (deep nesting, many branches)?
3. Are there common data structures (stacks, queues, trees) that would make it cleaner?
4. Are there any unused parameters?
5. Are there unnecessary type casts that could be moved to function arguments?
6. Is it testable without mocking core infrastructure (DB, redis, etc.)? If not, can it be integration-tested?
7. Does it have hidden untested dependencies that could be factored into arguments?
8. Brainstorm 3 better function names — is the current one best and consistent with the codebase?

**MUST NOT** refactor out a separate function unless:
- It will be reused elsewhere, OR
- It's the only way to unit-test otherwise untestable logic, OR
- The original is extremely hard to follow even with self-explanatory code

---

## Writing Tests Best Practices

When evaluating whether a test is good, use this checklist:

1. SHOULD parameterize inputs; never embed unexplained literals like `42` or `"foo"` directly.
2. SHOULD NOT add a test unless it can fail for a real defect.
3. SHOULD ensure the test description states exactly what the final `expect` verifies.
4. SHOULD compare results to independent, pre-computed expectations — never reuse the function's output as the oracle.
5. SHOULD follow the same lint, type-safety, and style rules as prod code.
6. SHOULD express invariants or axioms (commutativity, idempotence, round-trip) using `fast-check` where practical.
7. Unit tests for a function should be grouped under `describe(functionName, () => ...)`.
8. Use `expect.any(...)` for parameters that can be anything (e.g. variable IDs).
9. ALWAYS use strong assertions: `expect(x).toEqual(1)` over `expect(x).toBeGreaterThanOrEqual(1)`.
10. SHOULD test edge cases, realistic input, unexpected input, and value boundaries.
11. SHOULD NOT test conditions caught by the type checker.
