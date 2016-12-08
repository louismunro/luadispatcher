--[[ 
HAProxy Lua scripting example. 
This code will dynamically call redis and set the req.action variable.
The variable can then be used in the HAProxy configuration to select a backend
like this: 
 
listen proxy
   bind 127.0.0.1:10001
   http-request lua.select
   use_backend %[var(req.action)]
   default_backend portal

Tested on HAProxy 1.7.0.
This code requires lua 5.3, the luasocket library and the redis-lua library ]]


local redis = require("redis");

core.register_action("select", { "http-req" }, function(txn) 
    local client = redis.connect("unix:///var/run/redis/redis.sock");
    client:ping();
    -- TODO deal with connection errors to redis

    local backend = nil
    local checks = { check_client_ip, check_header, check_query }
    for i,check in ipairs(checks) do 
        backend = check(txn,client)
        -- first match wins and exit the loop
        if backend then 
            txn:set_var("req.action",backend)
            break
        end
    end
end)


function check_client_ip(txn, client) 
    core.Debug("Checking client IP")
    local ip = txn.sf:src()
    local mac = ip2mac(ip)
    if  client:sismember('pf::set::parking', mac) then 
        core.Debug("Match in pf::set::parking. Dispatching to parking backend")
        return 'parking'
    elseif client:sismember('pf::set::tarpit', mac) then 
        core.Debug("Match in pf::set::tarpit. Dispatching to tarpit backend")
        return 'tp'
    else 
        return nil
    end
end

function check_header(txn, client)
   core.Debug("Checking headers")
   local headers = txn.http:req_get_headers()
   local UA =  headers["user-agent"][0]
   local host = headers["host"][0]

   local hdr = { UA, host }
   for i,v in ipairs(hdr) do
       if  client:sismember('pf::set::parking', v) then 
           core.Debug("Match in pf::set::parking. Dispatching to parking backend")
           return 'parking'
       elseif client:sismember('pf::set::tarpit', v) then 
           core.Debug("Match in pf::set::tarpit. Dispatching to tarpit backend")
           return 'tp'
       end
   end
   return nil
end

function check_query(txn, client)
    core.Debug("Checking query string")
    local path = txn.sf:path()
    if  client:sismember('pf::set::parking', path) then 
        core.Debug("Match in pf::set::parking. Dispatching to parking backend")
       return 'parking'
    elseif client:sismember('pf::set::tarpit', path) then 
        core.Debug("Match in pf::set::tarpit. Dispatching to tarpit backend")
       return 'tp'
    end
    return nil
end

function ip2mac(ip)
    -- TODO Implement call to redis to match ip2mac
    return "aa:bb:cc:dd:ee:ff"
end 
