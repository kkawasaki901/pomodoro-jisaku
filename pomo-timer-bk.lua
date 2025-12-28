-- ########################
-- TODO: ポモドーロタイマー用のビープ音設定
-- ########################


-- 外部でPythonを使って10回ビープ音を鳴らす関数
local function beep_10_py_inline()
  vim.fn.jobstart({
    "python", "-c",
    "import time,winsound; [winsound.Beep(440,120) or time.sleep(0.25) for _ in range(10)]"
  }, { detach = true })
end

-- 外部でPythonを使って3回ビープ音を鳴らす関数
local function beep_3_py_inline()
  vim.fn.jobstart({
    "python", "-c",
    "import time,winsound; [winsound.Beep(880,120) or time.sleep(0.25) for _ in range(3)]"
  }, { detach = true })
end

-- ########################
-- TODO: スピナー
-- ########################

local spinner_timer
local notify_id
local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local frame_i = 1

local function start_spinner_notify()
  frame_i = 1

  notify_id = vim.notify("TIMER WORKING " .. frames[frame_i], vim.log.levels.INFO)

  spinner_timer = vim.loop.new_timer()
  spinner_timer:start(
    0,
    120, -- 回転速度（ms）
    vim.schedule_wrap(function()
      frame_i = frame_i % #frames + 1
      notify_id = vim.notify(
        "TIMER WORKING " .. frames[frame_i],
        vim.log.levels.INFO,
        { replace = notify_id }
      )
    end)
  )
end

local function stop_spinner_notify()
  if spinner_timer then
    spinner_timer:stop()
    spinner_timer:close()
    spinner_timer = nil
  end
end

-- ########################
-- TODO:ホワイトノイズ生成python呼び出し
-- #########################

-- ホワイトノイズを鳴らすかどうか
local enable_white_noise = true

local function start_noise()
  noise_job = vim.fn.jobstart({
    "python", "-c",
    [[
import numpy as np, sounddevice as sd, signal, sys
SAMPLERATE=44100
VOLUME=0.01
running=True
def handler(sig,frame):
    global running; running=False
signal.signal(signal.SIGTERM,handler)
signal.signal(signal.SIGINT,handler)
def callback(outdata,frames,time,status):
    if not running: raise sd.CallbackStop()
    outdata[:] = np.random.randn(frames,1)*VOLUME
with sd.OutputStream(samplerate=SAMPLERATE,channels=1,callback=callback):
    while running: sd.sleep(100)
]]
  }, { detach = true })
end

--[[
local function start_noise()
    noise_job = vim.fn.jobstart(
      { "python", white_noise_python_path },
      { detach = true }
    )
end
--]]

local function stop_noise()
    if noise_job then
      vim.fn.jobstop(noise_job)
    end
end

-- Neovim終了時にノイズ停止
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    stop_noise()
  end,
})

-- ########################
-- TODO: ポモドーロタイマー用のNotifierクラス
-- ########################

-- Notifierクラスの定義
local TestNotifier = {}

TestNotifier.new = function(timer, _)
  return setmetatable({ timer = timer }, { __index = TestNotifier })
end

--- タイマーのtickごと
function TestNotifier.tick(self)
  -- ここでは何もしない
end

-- タイマー開始時
function TestNotifier.start(self)
  start_spinner_notify()
  beep_3_py_inline()
  if enable_white_noise then
    start_noise()
  end
end

-- タイマー終了時
-- 聞き逃さないように10回鳴らす
function TestNotifier.done(self)
  stop_spinner_notify()
  vim.notify("TIMER DONE!", vim.log.levels.WARN)
  if enable_white_noise then
    stop_noise()
  end
  beep_10_py_inline()
end

