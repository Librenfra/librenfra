-- Librenfra: oturum açmış bir kullanıcı, başlıktaki From: ve Sender: alanlarında yalnızca
-- zarf göndereni olarak kullandığı adresi gösterebilir. Zarf göndereninin kullanıcıya ait
-- olduğunu Postfix denetler (smtpd_sender_login_maps); bu kural başlığı ona bağlar.
local rspamd_util = require "rspamd_util"

local function lower_addr(a)
  return a and a.addr and a.addr:lower() or nil
end

rspamd_config:register_symbol({
  name = 'LIBRENFRA_FORGED_HEADER_FROM',
  type = 'prefilter',
  priority = 10,
  callback = function(task)
    if not task:get_user() then return false end
    local env = task:get_from('smtp')
    local env_addr = env and lower_addr(env[1])
    local shown = {}
    for _, a in ipairs(task:get_from('mime') or {}) do table.insert(shown, a) end
    local sender = task:get_header('Sender')
    if sender then
      for _, a in ipairs(rspamd_util.parse_mail_address(sender, task:get_mempool()) or {}) do
        table.insert(shown, a)
      end
    end
    for _, a in ipairs(shown) do
      local addr = lower_addr(a)
      if not env_addr or addr ~= env_addr then
        task:set_pre_result('reject', 'Baslik adresi (' .. tostring(addr) .. ') hesaba ait degil', 'librenfra')
        return true
      end
    end
    return false
  end,
})
