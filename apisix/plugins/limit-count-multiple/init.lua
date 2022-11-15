--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local limit_local_new = require("resty.limit.count").new
local core = require("apisix.core")
local apisix_plugin = require("apisix.plugin")
local tab_insert = table.insert
local ipairs = ipairs
local pairs = pairs

local RATELIMIT_LIMIT     = "RateLimit-Limit"
local RATELIMIT_REMAINING = "RateLimit-Remaining"

local X_RATELIMIT_LIMIT = {
  second = "X-RateLimit-Limit-Second",
  minute = "X-RateLimit-Limit-Minute",
  hour   = "X-RateLimit-Limit-Hour",
}

local X_RATELIMIT_REMAINING = {
  second = "X-RateLimit-Remaining-Second",
  minute = "X-RateLimit-Remaining-Minute",
  hour   = "X-RateLimit-Remaining-Hour",
}

local plugin_name = "limit-count-multiple"
local limit_redis_cluster_new
local limit_redis_new
do
    local redis_src = "apisix.plugins.limit-count-multiple.limit-count-redis"
    limit_redis_new = require(redis_src).new

    local cluster_src = "apisix.plugins.limit-count-multiple.limit-count-redis-cluster"
    limit_redis_cluster_new = require(cluster_src).new
end
local lrucache = core.lrucache.new({
    type = 'plugin', serial_creating = true,
})
local group_conf_lru = core.lrucache.new({
    type = 'plugin',
})


local policy_to_additional_properties = {
    redis = {
        properties = {
            redis_host = {
                type = "string", minLength = 2
            },
            redis_port = {
                type = "integer", minimum = 1, default = 6379,
            },
            redis_password = {
                type = "string", minLength = 0,
            },
            redis_database = {
                type = "integer", minimum = 0, default = 0,
            },
            redis_timeout = {
                type = "integer", minimum = 1, default = 1000,
            },
        },
        required = {"redis_host"},
    },
    ["redis-cluster"] = {
        properties = {
            redis_cluster_nodes = {
                type = "array",
                minItems = 2,
                items = {
                    type = "string", minLength = 2, maxLength = 100
                },
            },
            redis_password = {
                type = "string", minLength = 0,
            },
            redis_timeout = {
                type = "integer", minimum = 1, default = 1000,
            },
            redis_cluster_name = {
                type = "string",
            },
        },
        required = {"redis_cluster_nodes", "redis_cluster_name"},
    },
}
local schema = {
    type = "object",
    properties = {
        second = {type = "integer",  exclusiveMinimum = 0},
        minute = {type = "integer",  exclusiveMinimum = 0},
        hour   = {type = "integer",  exclusiveMinimum = 0},
        group  = {type = "string"},
        key    = {type = "string", default = "remote_addr"},
        key_type = {type = "string",
            enum = {"var", "var_combination", "constant"},
            default = "var",
        },
        rejected_code = {
            type = "integer", minimum = 200, maximum = 599, default = 503
        },
        rejected_msg = {
            type = "string", minLength = 1
        },
        policy = {
            type = "string",
            enum = {"local", "redis", "redis-cluster"},
            default = "local",
        },
        allow_degradation = {type = "boolean", default = false},
        show_limit_quota_header = {type = "boolean", default = true}
    },
    anyof = {
        {required = {"second"}},
        {required = {"minute"}},
        {required = {"hour"}},
    },
    ["if"] = {
        properties = {
            policy = {
                enum = {"redis"},
            },
        },
    },
    ["then"] = policy_to_additional_properties.redis,
    ["else"] = {
        ["if"] = {
            properties = {
                policy = {
                    enum = {"redis-cluster"},
                },
            },
        },
        ["then"] = policy_to_additional_properties["redis-cluster"],
    }
}

local schema_copy = core.table.deepcopy(schema)

local _M = {
    schema = schema
}


local function group_conf(conf)
    return conf
end


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    if conf.group then
        -- means that call by some plugin not support
        if conf._vid then
            return false, "group is not supported"
        end

        local fields = {}
        -- When the goup field is configured,
        -- we will use schema_copy to get the whitelist of properties,
        -- so that we can avoid getting injected properties.
        for k in pairs(schema_copy.properties) do
            tab_insert(fields, k)
        end
        local extra = policy_to_additional_properties[conf.policy]
        if extra then
            for k in pairs(extra.properties) do
                tab_insert(fields, k)
            end
        end

        local prev_conf = group_conf_lru(conf.group, "", group_conf, conf)

        for _, field in ipairs(fields) do
            if not core.table.deep_eq(prev_conf[field], conf[field]) then
                core.log.error("previous limit-conn group ", prev_conf.group,
                            " conf: ", core.json.encode(prev_conf))
                core.log.error("current limit-conn group ", conf.group,
                            " conf: ", core.json.encode(conf))
                return false, "group conf mismatched"
            end
        end
    end

    return true
end


local function create_limit_obj(conf, period, limit)
    core.log.info("create new limit-count-multiple plugin instance")

    -- unit: second
    local time_window = {
        second = 1,
        minute = 60,
        hour   = 3600
    }

    if not conf.policy or conf.policy == "local" then
        return limit_local_new("plugin-" .. plugin_name, limit,
                                time_window[period])
    end

    if conf.policy == "redis" then
        return limit_redis_new("plugin-" .. plugin_name,
                                limit, time_window[period], conf)
    end

    if conf.policy == "redis-cluster" then
        return limit_redis_cluster_new("plugin-" .. plugin_name, limit,
                                time_window[period], conf)
    end

    return nil
end


local function gen_limit_key(conf, ctx, key, period)
    if conf.group then
        return conf.group .. ':' .. key .. ":" .. period
    end

    -- here we add a separator ':' to mark the boundary of the prefix and the key itself
    -- Here we use plugin-level conf version to prevent the counter from being resetting
    -- because of the change elsewhere.
    -- A route which reuses a previous route's ID will inherits its counter.
    local new_key = ctx.conf_type .. ctx.conf_id .. ':' .. apisix_plugin.conf_version(conf)
                    .. ':' .. key .. ":" .. period
    if conf._vid then
        -- conf has _vid means it's from workflow plugin, add _vid to the key
        -- so that the counter is unique per action.
        return new_key .. ':' .. conf._vid
    end

    return new_key
end


local function gen_limit_obj(conf, ctx, period, limit)
    if conf.group then
        return lrucache(conf.group .. period, "", create_limit_obj, conf, period, limit)
    end

    local extra_key
    if conf._vid then
        extra_key = conf.policy .. '#' .. period .. '#' .. conf._vid
    else
        extra_key = conf.policy .. '#' .. period
    end

    return core.lrucache.plugin_ctx(lrucache, ctx, extra_key, create_limit_obj, conf, period, limit)
end


function _M.rate_limit(conf, ctx)
    core.log.info("ver: ", ctx.conf_version)

    local limits = {
        second = conf.second,
        minute = conf.minute,
        hour   = conf.hour
    }

    local lims = {}
    for period, limit in pairs(limits) do
        local lim, err = gen_limit_obj(conf, ctx, period, limit)

        if not lim then
            core.log.error("failed to fetch limit.count object: ", err)
            if conf.allow_degradation then
                return
            end
            return 500
        end

        lims[period] = lim
    end

    local conf_key = conf.key
    local key
    if conf.key_type == "var_combination" then
        local err, n_resolved
        key, err, n_resolved = core.utils.resolve_var(conf_key, ctx.var)
        if err then
            core.log.error("could not resolve vars in ", conf_key, " error: ", err)
        end

        if n_resolved == 0 then
            key = nil
        end
    elseif conf.key_type == "constant" then
        key = conf_key
    else
        key = ctx.var[conf_key]
    end

    if key == nil then
        core.log.info("The value of the configured key is empty, use client IP instead")
        -- When the value of key is empty, use client IP instead
        key = ctx.var["remote_addr"]
    end

    local limit
    local rest
    local stop
    local err
    for period, lim in pairs(lims) do
        local limit_key = gen_limit_key(conf, ctx, key, period)
        local delay, remaining = lim:incoming(limit_key, true)

        if conf.show_limit_quota_header then
            local left = delay and remaining or 0

            if not limit or left < rest then
                limit = limits[period]
                rest = left
            end

            core.response.set_header(X_RATELIMIT_LIMIT[period], limits[period],
                X_RATELIMIT_REMAINING[period], left, RATELIMIT_LIMIT, limit,
                RATELIMIT_REMAINING, rest)
        end

        if not delay then
            err = remaining
            stop = true
        end
    end

    if stop then
        if err == "rejected" then
            if conf.rejected_msg then
                return conf.rejected_code, { error_msg = conf.rejected_msg }
            end
            return conf.rejected_code
        end

        core.log.error("failed to limit count: ", err)
        if conf.allow_degradation then
            return
        end
        return 500, {error_msg = "failed to limit count"}
    end

end


return _M
