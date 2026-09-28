// session-env — makes the session facts unmissable for small local models.
//
// opencode already puts a minimal <env> block in the system prompt, but small
// models (qwen3:14b) routinely ignore it and claim they have "no working
// directory" / "no access to your system". This plugin appends the same facts
// as an explicit, self-describing block so the model cannot miss them.
export const SessionEnv = async ({ directory, worktree, project }) => {
  const dir = directory || process.cwd()
  const root = worktree || dir
  return {
    "experimental.chat.system.transform": async (input, output) => {
      if (!output || !Array.isArray(output.system)) return
      output.system.push(
        [
          "<session-facts>",
          `Your working directory is: ${dir}`,
          `Project root (git worktree): ${root}`,
          `Project id: ${(project && project.id) || "unknown"}`,
          "You have real file and shell access through these tools: bash, glob, grep, read, edit, write, task, todowrite, webfetch, skill.",
          "Never say that you have no working directory, that you are a virtual assistant without access to the user's system, that you cannot read files, or that you cannot run shell commands.",
          'If asked which folder or project you are in, answer with the paths above. Call bash with "pwd" only if the user wants live verification.',
          "</session-facts>",
        ].join("\n"),
      )
    },
  }
}
