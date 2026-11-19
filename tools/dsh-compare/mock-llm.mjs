// Mock model for the DSH vs codeagent UI comparison. OpenAI Chat Completions on
// 127.0.0.1, streamed. Serves both apps with identical content:
//   message contains "ask me"  -> question tool (DSH ask_user_question / codeagent AskUserQuestion)
//   message contains "bash"    -> shell tool (DSH bash with sandbox escalation / codeagent Bash)
//   otherwise                  -> read tool on R/demo.R
// After a tool result it streams the same markdown reply. No network beyond localhost.
import http from 'node:http';
import fs from 'node:fs';

const PORT = Number(process.env.MOCK_PORT || 18080);
const LOG = process.env.MOCK_LOG || '/tmp/dsh-compare-mock.log';
const log = (...a) => fs.appendFileSync(LOG, a.join(' ') + '\n');

const REPLY = [
  '## Summary of `R/demo.R`',
  '',
  'The script builds a vector and prints its mean.',
  '',
  '| Step | Code | Result |',
  '|---|---|---|',
  '| 1 | `x <- 1:10` | integer vector |',
  '| 2 | `mean(x)` | `5.5` |',
  '',
  '```r',
  'x <- 1:10',
  'mean(x)',
  '#> [1] 5.5',
  '```',
  '',
  '> Tip: use `summary(x)` for quartiles as well.',
  '',
  '- [x] read the file',
  '- [ ] add tests',
].join('\n');

const QUESTION = {
  header: 'Output',
  question: 'Which output format do you want for the summary?',
  options: [
    ['Table (Recommended)', 'One row per step'],
    ['Bullet list', 'Short prose bullets'],
    ['Plot', 'A small chart of x'],
  ],
};

function textOf(m) {
  return typeof m.content === 'string' ? m.content : (m.content || []).map(p => p.text || '').join(' ');
}

function plan(tools, userText) {
  const names = (tools || []).map(t => t.function?.name).filter(Boolean);
  const has = n => names.includes(n);
  if (/ask me/i.test(userText)) {
    if (has('ask_user_question')) return ['ask_user_question', { questions: [{ id: 'q1', header: QUESTION.header,
      question: QUESTION.question, multiSelect: false,
      options: QUESTION.options.map(([label, description]) => ({ label, description })) }] }];
    if (has('AskUserQuestion')) return ['AskUserQuestion', { questions: [{ header: QUESTION.header,
      question: QUESTION.question, multiSelect: false,
      options: QUESTION.options.map(([label, description]) => ({ label, description })) }],
      _intent: 'Ask for the output format' }];
  }
  if (/bash/i.test(userText)) {
    const command = 'Rscript -e "summary(1:10)" > /tmp/summary.txt';
    if (has('bash')) return ['bash', { command, description: 'Run the summary in R',
      sandbox_permissions: 'danger-full-access', justification: 'Write the summary to /tmp, outside the workspace.' }];
    if (has('Bash')) return ['Bash', { command, description: 'Run the summary in R', _intent: 'Run the summary in R' }];
  }
  if (has('read')) return ['read', { file_path: 'R/demo.R' }];
  if (has('Read')) return ['Read', { file_path: 'R/demo.R', _intent: 'Read R/demo.R' }];
  return null;
}

const sse = (res, obj) => res.write('data: ' + JSON.stringify(obj) + '\n\n');

http.createServer((req, res) => {
  let body = '';
  req.on('data', c => (body += c));
  req.on('end', async () => {
    if (req.url.endsWith('/models')) {
      res.writeHead(200, { 'content-type': 'application/json' });
      return res.end(JSON.stringify({ object: 'list', data: [{ id: 'mock-model', object: 'model' }] }));
    }
    let j = {};
    try { j = JSON.parse(body || '{}'); } catch {}
    const msgs = j.messages || [];
    const users = msgs.filter(m => m.role === 'user').map(textOf);
    // The current turn starts after the last final answer (an assistant message
    // without tool calls). Its user messages -- DSH adds context as extra user
    // messages -- decide the tool; a tool result inside it means "answer now".
    let start = 0;
    msgs.forEach((m, i) => { if (m.role === 'assistant' && !(m.tool_calls || []).length) start = i + 1; });
    const turn = msgs.slice(start);
    const userText = turn.filter(m => m.role === 'user').map(textOf).join('\n');
    const toolDone = turn.some(m => m.role === 'tool');
    log('req msgs=', msgs.length, 'tool=', toolDone, 'stream=', !!j.stream, 'user=', (users.at(-1) || '').slice(0, 50));
    const base = { id: 'c' + Date.now(), object: 'chat.completion.chunk', created: Math.floor(Date.now() / 1000), model: j.model || 'mock-model' };
    const usage = { prompt_tokens: 1200, completion_tokens: 180, total_tokens: 1380 };
    const step = toolDone ? null : plan(j.tools, userText);
    if (!j.stream) {
      res.writeHead(200, { 'content-type': 'application/json' });
      const message = step
        ? { role: 'assistant', content: 'Let me look at the file first.',
            tool_calls: [{ id: 'call_' + Date.now(), type: 'function', function: { name: step[0], arguments: JSON.stringify(step[1]) } }] }
        : { role: 'assistant', content: /title/i.test(userText) ? 'Summary of R/demo.R' : REPLY };
      return res.end(JSON.stringify({ id: base.id, object: 'chat.completion', model: base.model,
        choices: [{ index: 0, message, finish_reason: step ? 'tool_calls' : 'stop' }], usage }));
    }
    res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache', connection: 'keep-alive' });
    if (step) {
      sse(res, { ...base, choices: [{ index: 0, delta: { role: 'assistant', content: 'Let me look at the file first.' } }] });
      sse(res, { ...base, choices: [{ index: 0, delta: { tool_calls: [{ index: 0, id: 'call_' + Date.now(), type: 'function', function: { name: step[0], arguments: '' } }] } }] });
      sse(res, { ...base, choices: [{ index: 0, delta: { tool_calls: [{ index: 0, function: { arguments: JSON.stringify(step[1]) } }] } }] });
      sse(res, { ...base, choices: [{ index: 0, delta: {}, finish_reason: 'tool_calls' }] });
    } else {
      const text = /title/i.test(userText) && msgs.length <= 2 ? 'Summary of R/demo.R' : REPLY;
      for (const piece of text.match(/[\s\S]{1,24}/g)) {
        sse(res, { ...base, choices: [{ index: 0, delta: { content: piece } }] });
        await new Promise(r => setTimeout(r, 10));
      }
      sse(res, { ...base, choices: [{ index: 0, delta: {}, finish_reason: 'stop' }] });
    }
    sse(res, { ...base, choices: [], usage });
    res.write('data: [DONE]\n\n');
    res.end();
  });
}).listen(PORT, '127.0.0.1', () => log('mock listening', PORT));
