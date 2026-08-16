--- Debug Adapter Protocol wire framing: `Content-Length: N\r\n\r\n<N bytes
--- of JSON>`, the same header-then-length-prefixed-body shape the
--- Language Server Protocol uses (confirmed against the real DAP spec —
--- https://microsoft.github.io/debug-adapter-protocol/overview — "Base
--- Protocol" section, which literally says "same as the base protocol
--- used by the language server protocol"). Pure encode/decode, no
--- process or buffer involved — mep.dap.client owns wiring this to a
--- real spawned adapter's stdio.
local M = {}

--- Frame `payload` (a plain table — a request/response/event) as one
--- complete DAP message, ready to write to an adapter's stdin.
function M.encode(payload)
  local body = vim.json.encode(payload)
  return string.format('Content-Length: %d\r\n\r\n%s', #body, body)
end

--- Extract every complete message from `buffer` (raw accumulated bytes
--- — possibly spanning several chunks, possibly holding more than one
--- message, possibly ending mid-message). Returns `messages` (a list of
--- decoded tables, in arrival order) and `remainder` (whatever's left in
--- `buffer` after the last complete message — pass straight back in as
--- `buffer` on the next call). A message whose body fails to decode as
--- JSON is dropped rather than raised — one malformed message shouldn't
--- take the whole session down; a header this function can't parse at
--- all (no `Content-Length`) stops extraction and leaves the rest of
--- `buffer` untouched, since without a reliable length there's no way to
--- know where the next message would even start.
function M.parse_messages(buffer)
  local messages = {}
  while true do
    local header_end = buffer:find('\r\n\r\n', 1, true)
    if not header_end then
      break
    end
    local header = buffer:sub(1, header_end - 1)
    local length = tonumber(header:match('Content%-Length:%s*(%d+)'))
    if not length then
      break
    end
    local body_start = header_end + 4
    local body_end = body_start + length - 1
    if #buffer < body_end then
      break
    end
    local body = buffer:sub(body_start, body_end)
    local ok, decoded = pcall(vim.json.decode, body)
    if ok then
      messages[#messages + 1] = decoded
    end
    buffer = buffer:sub(body_end + 1)
  end
  return messages, buffer
end

return M
