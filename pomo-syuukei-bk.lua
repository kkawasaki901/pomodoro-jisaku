-- ########################
-- TODO: jsonでpomdoro集計
-- ########################

-- ===== Focus JSON report =====
local focus_json_path = vim.fn.stdpath("config") .. "/focus.json"

local function read_file(path)
  local f = io.open(focus_json_path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end



-- ファイルが存在しなければ作成
if vim.fn.filereadable(focus_json_path) == 0 then
  local f = io.open(focus_json_path, "w")
  if f then
    f:write(vim.json.encode({ entries = {} }) .. "\n")
    f:close()
  else
    vim.notify("Failed to create focus.json", vim.log.levels.ERROR)
  end
end


local function open_scratch(lines, title)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, title or "FocusReport")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, buf)
end

local function sorted_keys(map)
  local keys = {}
  for k in pairs(map) do table.insert(keys, k) end
  table.sort(keys)
  return keys
end

local function max_value(map)
  local m = 0
  for _, v in pairs(map) do if v > m then m = v end end
  return m
end

local function bar(minutes, max_minutes, width)
  width = width or 24
  if max_minutes <= 0 then return "" end
  local n = math.floor((minutes / max_minutes) * width + 0.5)
  if n < 0 then n = 0 end
  if n > width then n = width end
  return string.rep("█", n) .. string.rep(" ", width - n)
end

local function week_key_from_day(day)
  -- day: "YYYY-MM-DD" -> その週の月曜 "YYYY-MM-DD"
  local y = tonumber(day:sub(1, 4))
  local m = tonumber(day:sub(6, 7))
  local d = tonumber(day:sub(9, 10))
  local t = os.time({ year = y, month = m, day = d, hour = 12 })
  local wday = tonumber(os.date("%w", t)) -- 0=Sun..6=Sat
  local offset = (wday == 0) and 6 or (wday - 1) -- Mon=0..Sun=6
  local monday_t = t - offset * 24 * 60 * 60
  return os.date("%Y-%m-%d", monday_t)
end

local function weekday_label_from_day(day)
  local y = tonumber(day:sub(1, 4))
  local m = tonumber(day:sub(6, 7))
  local d = tonumber(day:sub(9, 10))
  local t = os.time({ year = y, month = m, day = d, hour = 12 })
  local w = tonumber(os.date("%w", t)) -- 0..6
  local labels = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
  return labels[w + 1]
end

local function focus_json_report(opts)
  opts = opts or {}
  local path = opts.path or vim.fn.expand("~/focus.json")
  local only_work = (opts.only_work ~= false)

  local raw = read_file(focus_json_path)
  if not raw then
    vim.notify("focus: file not found: " .. focus_json_path, vim.log.levels.ERROR)
    return
  end

  local ok, data = pcall(vim.json.decode, raw)
  if not ok or type(data) ~= "table" then
    vim.notify("focus: invalid json: " .. path, vim.log.levels.ERROR)
    return
  end

  local entries = data.entries or {}
  local day_sum, week_sum, month_sum, wday_sum = {}, {}, {}, {}
  local total, count = 0, 0

  for _, e in ipairs(entries) do
    local day = e.date
    local cat = e.category
    local minutes = tonumber(e.time)

    if type(day) == "string" and minutes then
      if (not only_work) or (cat == "work") then
        local week = week_key_from_day(day)
        local month = day:sub(1, 7)
        local wday = weekday_label_from_day(day)

        day_sum[day] = (day_sum[day] or 0) + minutes
        week_sum[week] = (week_sum[week] or 0) + minutes
        month_sum[month] = (month_sum[month] or 0) + minutes
        wday_sum[wday] = (wday_sum[wday] or 0) + minutes

        total = total + minutes
        count = count + 1
      end
    end
  end

  local out = {}
  table.insert(out, ("# Focus report (JSON)  %s"):format(path))
  table.insert(out, "")
  table.insert(out, ("- mode: %s"):format(only_work and "work only" or "all categories"))
  table.insert(out, ("- entries: %d"):format(count))
  table.insert(out, ("- total: %d min (%.2f h)"):format(total, total / 60))
  table.insert(out, "")

  -- By day
  table.insert(out, "## By day")
  table.insert(out, "")
  table.insert(out, "| date | minutes | hours | graph |")
  table.insert(out, "|---:|---:|---:|:---|")
  local day_max = max_value(day_sum)
  for _, d in ipairs(sorted_keys(day_sum)) do
    local m = day_sum[d]
    table.insert(out, string.format("| %s | %d | %.2f | `%s` |", d, m, m / 60, bar(m, day_max, 24)))
  end
  table.insert(out, "")

  -- By week
  table.insert(out, "## By week (Mon-based)")
  table.insert(out, "")
  table.insert(out, "| week (Mon) | minutes | hours | graph |")
  table.insert(out, "|---:|---:|---:|:---|")
  local week_max = max_value(week_sum)
  for _, w in ipairs(sorted_keys(week_sum)) do
    local m = week_sum[w]
    table.insert(out, string.format("| %s | %d | %.2f | `%s` |", w, m, m / 60, bar(m, week_max, 24)))
  end
  table.insert(out, "")

  -- By month
  table.insert(out, "## By month")
  table.insert(out, "")
  table.insert(out, "| month | minutes | hours | graph |")
  table.insert(out, "|---:|---:|---:|:---|")
  local month_max = max_value(month_sum)
  for _, mo in ipairs(sorted_keys(month_sum)) do
    local m = month_sum[mo]
    table.insert(out, string.format("| %s | %d | %.2f | `%s` |", mo, m, m / 60, bar(m, month_max, 24)))
  end
  table.insert(out, "")

  -- By weekday
  table.insert(out, "## By weekday")
  table.insert(out, "")
  table.insert(out, "| weekday | minutes | hours | graph |")
  table.insert(out, "|:---|---:|---:|:---|")
  local order = { "Mon","Tue","Wed","Thu","Fri","Sat","Sun" }
  local wday_max = max_value(wday_sum)
  for _, wd in ipairs(order) do
    local m = wday_sum[wd] or 0
    table.insert(out, string.format("| %s | %d | %.2f | `%s` |", wd, m, m / 60, bar(m, wday_max, 24)))
  end

  open_scratch(out, "FocusReport(JSON)")
end

vim.api.nvim_create_user_command("FocusJsonReport", function()
  focus_json_report({ path = focus_json_path, only_work = true })
end, {})

vim.api.nvim_create_user_command("FocusJsonReportAll", function()
  focus_json_report({ path = focus_json_path, only_work = false })
end, {})

-- ===== Focus logger (JSON) =====
local focus = {}

focus.path = focus_json_path


local function write_file(path, content)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local f, err = io.open(focus_json_path, "w")
  if not f then
    vim.notify("focus: failed to write file: " .. (err or ""), vim.log.levels.ERROR)
    return false
  end
  f:write(content)
  f:close()
  return true
end

local function load_db(path)
  local raw = read_file(focus_json_path)
  if not raw or raw == "" then
    return { entries = {} }
  end
  local ok, data = pcall(vim.json.decode, raw)
  if not ok or type(data) ~= "table" then
    return { entries = {} }
  end
  if type(data.entries) ~= "table" then
    data.entries = {}
  end
  return data
end

local function save_db(path, db)
  local ok, encoded = pcall(vim.json.encode, db, { indent = true })
  if not ok then
    vim.notify("focus: json encode failed", vim.log.levels.ERROR)
    return false
  end
  -- 読みやすさのために末尾改行
  return write_file(path, encoded .. "\n")
end

local function today()
  return os.date("%Y-%m-%d")
end

local function now_hm()
  return os.date("%H:%M")
end

local function to_number(s)
  local n = tonumber(s)
  if not n then return nil end
  if n < 0 then return nil end
  return n
end

local function add_entry_interactive(opts)
  opts = opts or {}
  local path = opts.path or focus.path

  -- 1) date
  vim.ui.input({
    prompt = "Date (YYYY-MM-DD): ",
    default = today(),
  }, function(date)
    if not date or date == "" then return end
    if not date:match("^%d%d%d%d%-%d%d%-%d%d$") then
      vim.notify("focus: invalid date format (use YYYY-MM-DD)", vim.log.levels.ERROR)
      return
    end

    -- 2) category
    local categories = opts.categories or { "work", "rest" }
    local default_cat = opts.default_category or "work"
    vim.ui.select(categories, {
      prompt = "Category: ",
      -- nvim 0.10+ なら default 使えます（無くてもOK）
      default = default_cat,
    }, function(category)
      if not category or category == "" then return end

      -- 3) title
      vim.ui.input({
        prompt = "Title (optional): ",
        default = opts.default_title or "",
      }, function(title)
        if title == nil then return end

        -- 4) minutes
        vim.ui.input({
          prompt = "Minutes: ",
          default = tostring(opts.default_minutes or (category == "work" and 25 or 5)),
        }, function(mins)
          if not mins or mins == "" then return end
          local minutes = to_number(mins)
          if not minutes then
            vim.notify("focus: minutes must be a non-negative number", vim.log.levels.ERROR)
            return
          end

          -- 5) save
          local db = load_db(path)
          table.insert(db.entries, {
            date = date,
            time = minutes,             -- 分
            category = category,        -- "work" / "rest"
            title = title,
            at = opts.include_at and now_hm() or nil, -- 任意: 時刻も残したい場合
          })

          if save_db(path, db) then
            vim.notify(
              ("focus: added (%s) %s %dmin %s"):format(date, category, minutes, title ~= "" and ("- " .. title) or ""),
              vim.log.levels.INFO
            )
          end
        end)
      end)
    end)
  end)
end

-- コマンド：:FocusAdd
vim.api.nvim_create_user_command("FocusAdd", function()
  add_entry_interactive({
    path = focus.path,
    include_at = false, -- 時刻も残したければ true
  })
end, {})

-- 便利コマンド：work/rest をワンアクション寄りに
vim.api.nvim_create_user_command("FocusAddWork", function()
  add_entry_interactive({
    path = focus.path,
    default_category = "work",
    default_minutes = 25,
    include_at = false,
  })
end, {})

vim.api.nvim_create_user_command("FocusAddRest", function()
  add_entry_interactive({
    path = focus.path,
    default_category = "rest",
    default_minutes = 5,
    include_at = false,
  })
end, {})

-- #########################
-- カスタムコマンド選択メニューポモドーロタイマー用
-- #########################

--[[
-- 後述の:PTにまとめられたのでこれはいらない
local pomo_items = {
  { label = "pomo_Report", cmd = "FocusJsonReport" },
  { label = "pomo_ReportAll", cmd = "FocusJsonReportAll" },
  { label = "pomo_Add", cmd = "FocusAdd" },
  { label = "pomo_AddWork", cmd = "FocusAddWork" },
  { label = "pomo_AddRest", cmd = "FocusAddRest" },
  { label = "TimerStart", cmd = "TimerStart" },
  { label = "TimerStop", cmd = "TimerStop" },
  { label = "TimerPause", cmd = "TimerPause" },
  { label = "TimerResume", cmd = "TimerResume" },
  { label = "TimerSession po", cmd = "TimerSession po" },
}


-- :PPに割り当て
vim.api.nvim_create_user_command("PP", function()
  vim.ui.select(pomo_items, {
    prompt = "pomo Commands",
    format_item = function(item) return item.label end,
  }, function(choice)
    if choice then
      vim.cmd(choice.cmd)
    end
  end)
end, {})
--]]

-- 例えば <leader>PP で開く
-- かぶったのでこれも使わない
-- vim.keymap.set("n", "<leader>PP", "<cmd>PP<CR>", { desc = "pomodoro Commands" })

-- ##########################
-- TODO: 自動記録
-- ##########################

local focus_json_path = vim.fn.stdpath("config") .. "/focus.json"

-- ===== JSON utils =====
local function ensure_focus_json(path)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  if vim.fn.filereadable(path) == 0 then
    local f = io.open(path, "w")
    if f then
      f:write(vim.json.encode({ entries = {} }) .. "\n")
      f:close()
    end
  end
end


local function append_entry(path, entry)
  ensure_focus_json(focus_json_path)
  local db = load_db(focus_json_path)
  table.insert(db.entries, entry)
  return write_file(focus_json_path, vim.json.encode(db, {indent = true}) .. "\n")
end

-- ===== FocusLogNotifier =====
local FocusLogNotifier = {}

FocusLogNotifier.new = function(timer, opts)
  return setmetatable({
    timer = timer,
    opts = opts or {},
    started_at = nil, -- os.time()
  }, { __index = FocusLogNotifier })
end

local function now_date() return os.date("%Y-%m-%d") end
local function now_time() return os.date("%H:%M:%S") end


local function minutes_from_seconds(sec)
  -- 秒→分（切り捨て）: 5分未満の判定と相性が良い
  return math.floor((tonumber(sec) or 0) / 60)
end

function FocusLogNotifier.start(self)
    self.started_at = os.time()
end

function FocusLogNotifier.tick(self, _) end

function FocusLogNotifier.done(self)
  -- vim.notify("FocusLogNotifier: done", vim.log.levels.INFO)

  -- 基本はタイマー設定時間から（started_at があるなら実測でもOK）
  -- local min = minutes_from_seconds(self.timer.time_limit)

  -- 5分未満は捨てる
  -- if min < (self.opts.min_minutes or 5) then return end

  append_entry(self.opts.path, {
    date = now_date(),
    at = now_time(),
    title = self.opts.title or (self.timer.name or "Work"),
    category = "work",
    time = minutes_from_seconds(os.time() - self.started_at) or min,
    status = "done",
  })
end

function FocusLogNotifier.stop(self)
  vim.notify("FocusLogNotifier: stopped", vim.log.levels.INFO)
  if not self.opts.log_stop then return end
  if not self.started_at then return end

  local elapsed_sec = os.time() - self.started_at
  local min = minutes_from_seconds(elapsed_sec)

  -- 5分未満は捨てる
  -- if min < (self.opts.min_minutes or 5) then return end

  append_entry(self.opts.path, {
    date = now_date(),
    at = now_time(),
    title = "**",
    category = "work",
    time = min,
    status = "stopped",
  })
end

-- ########################
-- TODO: 記録したjsonをvscodeで開く
-- ########################

vim.api.nvim_create_user_command("OpenFocusJsonInVSCode", function()
  vim.fn.jobstart({ "code", "--reuse-window", "--goto", focus_json_path }, { detach = true })
end, {})
