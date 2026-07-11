#!/usr/bin/env bun
// 语言考古学家 · 每日续写（CR-3 P3）。抄私库 batch_run.sh 管线：
// 词表挑 N 个还没语料的词 → 逐个 claude -p 生成 → 写 repo Resources/vocab-corpus/。
//
// 为什么是 bun 不是 bash：launchd hub spawn 的子进程写 ~/Desktop 下的 repo 会被
// TCC 挡（FDA 只给了 bun）。所以文件 IO 全在本进程；claude 子进程只碰
// argv/stdin/stdout（system prompt 用 --system-prompt 字符串直传，不读文件）。
//
// 用法：bun vocab-daily.ts [N]              （缺省 30，⧫ 粟粟拍的每日额度）
//       bun vocab-daily.ts --word <词>     （R3-3 考古按钮单词模式：成功打印 OUTFILE:<路径> 给 hub 回投）
import { readFileSync, readdirSync, writeFileSync, existsSync } from "node:fs"
import { join, dirname } from "node:path"

const WORD_MODE = process.argv[2] === "--word" ? (process.argv[3] ?? "").trim().toLowerCase() : null
if (process.argv[2] === "--word" && !WORD_MODE) {
  console.error("--word 需要词参数")
  process.exit(1)
}
const N = Math.max(1, parseInt(process.argv[2] ?? "30", 10) || 30)
const SCRIPT_DIR = import.meta.dir                       // <repo>/scripts/vocab
const WORD_LIST = join(SCRIPT_DIR, "词汇表_雅思加强版.txt")
const SYSTEM_PROMPT_FILE = join(SCRIPT_DIR, "语言考古学家_批量版.md")
const OUT_DIR = join(SCRIPT_DIR, "..", "Sources", "Marginalia", "Resources", "vocab-corpus")

const home = process.env.HOME ?? ""
const CLAUDE = [join(home, ".local", "bin", "claude"), "claude"].find((p) =>
  p === "claude" || existsSync(p)
)!

const words = readFileSync(WORD_LIST, "utf8").split("\n").map((w) => w.trim()).filter(Boolean)
const existing = new Set(
  readdirSync(OUT_DIR)
    .map((f) => /^\d{4}-(.+)\.md$/.exec(f)?.[1])
    .filter((w): w is string => !!w)
)
const systemPrompt = readFileSync(SYSTEM_PROMPT_FILE, "utf8")

// 词表行号 = 语料编号（%04d，与已有 355 篇一致）；重复词面（如 as×4）首个生成后其余跳过
const todo: Array<[number, string]> = []
if (WORD_MODE) {
  // 单词模式：已有语料直接回投现成文件（app 端已考古不出按钮，这是兜底）；
  // 词不在词表（聊天收的自由词）编号 0000
  if (existing.has(WORD_MODE)) {
    const f = readdirSync(OUT_DIR).find((f) => /^\d{4}-(.+)\.md$/.exec(f)?.[1] === WORD_MODE)
    if (f) {
      console.log(`already: ${WORD_MODE}`)
      console.log(`OUTFILE:${join(OUT_DIR, f)}`)
      process.exit(0)
    }
  }
  const li = words.indexOf(WORD_MODE)
  todo.push([li >= 0 ? li + 1 : 0, WORD_MODE])
} else {
  for (let i = 0; i < words.length && todo.length < N; i++) {
    if (!existing.has(words[i])) todo.push([i + 1, words[i]])
  }
}

console.log(WORD_MODE ? `单词模式：${WORD_MODE}` : `词表 ${words.length} · 已有 ${existing.size} · 本轮 ${todo.length}（额度 ${N}）`)

let ok = 0
let fail = 0
for (const [idx, word] of todo) {
  const padded = String(idx).padStart(4, "0")
  const outfile = join(OUT_DIR, `${padded}-${word}.md`)

  // 裸词会被当对话语汇（acknowledge=确认/assistant=助手——私库 355 篇里缺的
  // 0040/0081/0107/0247 全是这类词，她的 batch_run.sh 同样栽在这），包装成任务句消歧义
  const proc = Bun.spawn(
    [CLAUDE, "-p", "--model", "claude-opus-4-6", "--effort", "max",
     "--system-prompt", systemPrompt, "--max-turns", "1"],
    { stdin: new TextEncoder().encode(`本轮要考古的单词：${word}`), stdout: "pipe", stderr: "ignore" }
  )
  const killer = setTimeout(() => proc.kill(), 5 * 60_000)  // 单词 5min 顶
  const text = await new Response(proc.stdout).text()
  const code = await proc.exited
  clearTimeout(killer)

  // 幂等纪律同 batch_run.sh：>500B 才算有实质内容；失败不落盘 = 无残片
  if (code === 0 && text.length > 500) {
    writeFileSync(outfile, text)
    ok++
    console.log(`[${padded}] ✓ ${word} (${text.length}B)`)
    if (WORD_MODE) console.log(`OUTFILE:${outfile}`)
  } else {
    fail++
    console.log(`[${padded}] ✗ ${word} (exit=${code}, ${text.length}B)`)
  }
}

console.log(`done: ok=${ok} fail=${fail} 剩余缺口≈${words.length - existing.size - ok}`)
process.exit(fail > 0 && ok === 0 ? 1 : 0)
