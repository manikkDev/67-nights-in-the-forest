---
description: Run the full autonomous build loop — reads tasks from TASKS.md, implements each one, verifies via Roblox playtest, reviews with Groq evaluator, fixes errors, repeats until all tasks are done and verified
---

# Autonomous Build Loop

## Your Role

You are an autonomous build agent. Your job is to complete ALL tasks defined in TASKS.md, verify each one works via Roblox Studio playtest, get each one reviewed by the Groq evaluator, and only stop when everything is done and verified.

You have FULL CONTROL. Do not ask the user for clarification. Make reasonable decisions based on the task description and existing code patterns. The user has walked away — they expect you to handle everything.

## Prerequisites (Verify Before Starting)

Before beginning the loop, verify these are ready:

1. **Roblox Studio is open** with the project loaded and MCP connected
   - Call `mcp0_list_roblox_studios` to check
   - If no studios connected, STOP and tell the user to open Roblox Studio
2. **Rojo is running** (file sync from src/ to Studio)
   - The user should have rojo serve running — just assume it's working
3. **Python + dependencies installed**
   - Run: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py status`
   - If it fails with import errors, tell the user to run: `.orchestrator/venv/Scripts/python.exe -m pip install -r .orchestrator/requirements.txt`

## Loop Procedure

Follow these steps EXACTLY. This is a LOOP — after completing the final step, loop back to Step 1 until all tasks are done.

---

### Step 1: Initialize State (only on first run)

If `.orchestrator/state.json` does not exist:

1. Run: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py init`
2. This parses TASKS.md and creates the initial state
3. Log the start: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py log --level info --message "Autonomous build loop started"`

If state.json already exists, skip to Step 2 (this is a resume).

---

### Step 2: Check Budget

1. Run: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py check-budget`
2. Parse the JSON output
3. If `"exceeded": true`:
   - STOP immediately
   - Run: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py log --level error --message "Budget exceeded — stopping"`
   - Report to the user which limit was hit and current progress
   - Do NOT continue

---

### Step 3: Get Next Task

1. Run: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py get-next`
2. Parse the JSON output
3. If `"status": "all_done"`:
   - Skip to Step 9 (Final Verification)
4. If `"status": "found"`:
   - You now have the task details (title, instructions, referenced_files)
   - Continue to Step 4

---

### Step 4: Gather Context

1. Read the task's `instructions` and `instruction_list`
2. Read the task's `referenced_files` — these are files you should look at for context
3. Read the files mentioned in the task (use `read_file` tool)
4. Read `ARCHITECTURE.md` if it exists for project structure
5. Read `src/shared/Constants.luau` for game constants
6. Read any existing files in the directory where you'll be creating code
7. Understand the existing code patterns, naming conventions, and architecture
8. Increment iteration counter: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py increment-iteration`

**IMPORTANT**: Do NOT ask the user for clarification. Make decisions based on what you see in the existing code. Follow the same patterns, style, and architecture.

---

### Step 5: Implement the Task

1. Write the code for the current task
2. Follow existing code style (Luau, Knit framework patterns, naming conventions)
3. Create new files or modify existing ones as needed
4. Use the `edit`, `multi_edit`, or `write_to_file` tools to make changes
5. Save all changes (the tools auto-save)

**Code Quality Rules**:

- Always include proper error handling (pcall for network calls, nil checks)
- Follow the existing service/controller pattern in the codebase
- Use typed Luau where the existing code does
- Don't leave debug prints unless the existing code has them
- Match indentation and formatting of existing files

---

### Step 6: Verify via Playtest

This is the CRITICAL verification step. You must actually run a playtest and check for errors.

1. **Get Studio ID**: Call `mcp0_list_roblox_studios` to get the studio_id
2. **Get Studio State**: Call `mcp0_get_studio_state` with the studio_id
   - If already in play mode, stop it first: `mcp0_start_stop_play` with `is_start=false`
3. **Start Playtest**: Call `mcp0_start_stop_play` with `is_start=true` and the studio_id
4. **Wait**: Wait 15 seconds for the game to initialize (use a comment like "Waiting 15 seconds for playtest to initialize..." and then continue)
5. **Read Console**: Call `mcp0_get_console_output` with the studio_id
6. **Stop Playtest**: Call `mcp0_start_stop_play` with `is_start=false` and the studio_id
7. **Parse Console Output**: Look through the console text for:
   - Lines containing "error", "Error", "ERROR"
   - Lua stack traces ("Stack:", "attempt to index nil", "attempt to call nil")
   - Script errors (lines containing ".luau:" followed by line numbers and error messages)
   - Warnings related to the files you modified
8. **Filter**: Only count errors related to YOUR task's files (not pre-existing errors from other systems)

---

### Step 7: Handle Verification Results

**If there ARE errors related to your task**:

1. Run: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py mark-failed <task_id> --error "<error summary>"`
2. Log: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py log --level warning --message "Playtest errors found: <count>" --task-id <task_id>`
3. Read the error messages carefully
4. Fix the code that caused the errors
5. Go back to Step 6 (verify again)
6. Maximum 7 attempts per task (configured in config.yaml). If you hit 7 attempts:
   - Run: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py mark-blocked <task_id> --reason "Failed after 7 attempts: <last error>"`
   - Log: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py log --level error --message "Task blocked after max attempts" --task-id <task_id>`
   - Go back to Step 2 (move to next task)

**If there are NO errors** (playtest clean):

1. Take a screenshot for visual verification: `mcp0_screen_capture` with a capture*id like `task*<task*id>*<attempt>`
2. Continue to Step 8 (Evaluator Review)

---

### Step 8: Evaluator Review (Groq)

Now the independent evaluator reviews your work. This is a separate AI model (Llama 3.3 70B via Groq) that checks your code quality.

1. **Prepare evaluation input**: Create a JSON file at `.orchestrator/eval_input.json` with:

```json
{
    "task_title": "<task title>",
    "task_instructions": "<task instructions from TASKS.md>",
    "code_changes": "<paste the full code of all files you created or modified>",
    "playtest_result": {
        "passed": true,
        "errors": [],
        "warnings": ["<any warnings>"],
        "raw_output": "<last 2000 chars of console output>"
    },
    "attempt": <attempt number>,
    "previous_feedback": "<previous evaluator feedback if this is a retry, else null>"
}
```

2. **Run the evaluator**:

```
.orchestrator/venv/Scripts/python.exe .orchestrator/evaluator.py --input .orchestrator/eval_input.json --output .orchestrator/eval_output.json
```

3. **Read the result**: Read `.orchestrator/eval_output.json`
4. **Parse the result**: Look at `approved`, `score`, `issues`, `fix_instructions`

**If evaluator APPROVED** (approved=true AND score >= 6):

1. Run: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py mark-complete <task_id> --score <score> --notes "Evaluator approved"`
2. Log: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py log --level info --message "Task completed and approved (score: <score>)" --task-id <task_id>`
3. Go back to Step 2 (next task)

**If evaluator REJECTED** (approved=false OR score < 6):

1. Log: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py log --level warning --message "Evaluator rejected (score: <score>): <issues>" --task-id <task_id>`
2. Read the `fix_instructions` field carefully
3. Apply the fixes the evaluator suggested
4. Go back to Step 6 (verify via playtest again)
5. The task's attempt counter will eventually hit the limit — if it does, the task gets blocked

**If evaluator ERROR** (\_error=true in output):

1. The evaluator script failed (API issue, etc.)
2. Log: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py log --level warning --message "Evaluator error — relying on deterministic verification only" --task-id <task_id>`
3. Since the playtest already passed (Step 7), mark the task complete:
   - Run: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py mark-complete <task_id> --score 0 --notes "Evaluator unavailable — passed playtest verification only"`
4. Go back to Step 2 (next task)

---

### Step 9: Final Verification (when all tasks are done)

When `get-next` returns `"status": "all_done"`:

1. Log: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py log --level info --message "All tasks done — starting final verification"`
2. **Start a full playtest**: `mcp0_start_stop_play` with `is_start=true`
3. **Monitor for 60 seconds**: Every 10 seconds, call `mcp0_get_console_output` and check for errors
   - Do this 6 times (10s, 20s, 30s, 40s, 50s, 60s)
   - Collect all errors found
4. **Stop the playtest**: `mcp0_start_stop_play` with `is_start=false`
5. **Take a final screenshot**: `mcp0_screen_capture`

**If zero errors for 60 seconds**:

1. Run: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py set-final-verification --status passed --duration 60 --errors 0 --warnings 0`
2. Log: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py log --level info --message "FINAL VERIFICATION PASSED — all tasks complete, zero errors for 60 seconds"`
3. Run: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py status`
4. Report to the user:

   ```
   ✅ ALL TASKS COMPLETE AND VERIFIED

   Total tasks: N
   Completed: N
   Blocked: X
   Total iterations: N
   Total playtest errors fixed: N
   Final playtest: 60 seconds, zero errors

   Task breakdown:
   - Task 1: [title] — Score: X/10 ✅
   - Task 2: [title] — Score: X/10 ✅
   ...
   ```

**If errors found during final verification**:

1. Identify which task's code is causing the error
2. Run: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py set-final-verification --status failed --duration 60 --errors <count> --warnings <count>`
3. Log: `.orchestrator/venv/Scripts/python.exe .orchestrator/state_manager.py log --level error --message "Final verification FAILED — <count> errors found"`
4. Set that task back to pending in state.json (manually edit the file or use mark-failed)
5. Go back to Step 2 (fix the failing task)

---

## Hard Stop Conditions

Stop immediately and report to the user if ANY of these occur:

1. **Budget exceeded** — checked in Step 2
2. **Roblox Studio disconnected** — MCP calls fail. Tell the user to reconnect.
3. **All API keys exhausted** — Evaluator fails with \_error=true on every call. Continue with deterministic verification only (playtest), but warn the user.
4. **All tasks blocked** — Every task is in "blocked" status. Report what went wrong.
5. **Catastrophic error** — State file corruption, filesystem errors, etc.

---

## Rules

- **NEVER ask the user for input during the loop** — make decisions and proceed
- **ALWAYS verify via actual playtest** — never assume code works without testing
- **ALWAYS run the evaluator** after playtest passes — don't skip code review
- **ALWAYS update state.json** after each task status change
- **ALWAYS log events** — the user will review the log later
- **Follow existing code patterns** — match the style of files already in the project
- **Handle errors gracefully** — if something fails, log it and try to recover
- **Be thorough** — read referenced files, understand context, write quality code
- **Don't create unnecessary files** — only create what the task requires
- **Don't modify files outside the task scope** — unless necessary for integration
