#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
BEGIN {
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_shuffle();
no_root_location();

add_block_preprocessor(sub {
    my ($block) = @_;

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->error_log && !$block->no_error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests;

__DATA__

=== TEST 1: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count-multiple": {
                                "second": 3,
                                "minute": 1,
                                "hour": 1,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 2: pass
--- request
GET /hello
--- error_code: 200
--- response_headers
RateLimit-Limit: 1
RateLimit-Remaining: 0
X-RateLimit-Limit-Second: 3
X-RateLimit-Remaining-Second: 2
X-RateLimit-Limit-Minute: 1
X-RateLimit-Remaining-Minute: 0
X-RateLimit-Limit-Hour: 1
X-RateLimit-Remaining-Hour: 0



=== TEST 3: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count-multiple": {
                                "second": 3,
                                "minute": 2,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 4: pass
--- request
GET /hello
--- error_code: 200
--- response_headers
RateLimit-Limit: 2
RateLimit-Remaining: 1
X-RateLimit-Limit-Second: 3
X-RateLimit-Remaining-Second: 2
X-RateLimit-Limit-Minute: 2
X-RateLimit-Remaining-Minute: 1



=== TEST 5: pass
--- request
GET /hello
--- error_code: 200
--- response_headers
RateLimit-Limit: 2
RateLimit-Remaining: 0
X-RateLimit-Limit-Second: 3
X-RateLimit-Remaining-Second: 2
X-RateLimit-Limit-Minute: 2
X-RateLimit-Remaining-Minute: 0



=== TEST 6: up the limit
--- request
GET /hello
--- error_code: 503
--- response_headers
RateLimit-Limit: 2
RateLimit-Remaining: 0
X-RateLimit-Limit-Second: 3
X-RateLimit-Remaining-Second: 2
X-RateLimit-Limit-Minute: 2
X-RateLimit-Remaining-Minute: 0



=== TEST 7: set route(id: 1), change the config
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count-multiple": {
                                "second": 2,
                                "minute": 2,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 8: pass
--- request
GET /hello
--- error_code: 200
--- response_headers
RateLimit-Limit: 2
RateLimit-Remaining: 1
X-RateLimit-Limit-Second: 2
X-RateLimit-Remaining-Second: 1
X-RateLimit-Limit-Minute: 2
X-RateLimit-Remaining-Minute: 1



=== TEST 9: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count-multiple": {
                                "second": 1,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 10: up the limit
--- request
GET /hello
--- error_code: 200
--- response_headers
RateLimit-Limit: 1
RateLimit-Remaining: 0
X-RateLimit-Limit-Second: 1
X-RateLimit-Remaining-Second: 0



=== TEST 11: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count-multiple": {
                                "second": 3,
                                "minute": 1,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 12: up the limit
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 503, 503, 503]



=== TEST 13: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count-multiple": {
                                "second": 4,
                                "minute": 3,
                                "hour":   2,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 14: up the limit
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503, 503]



=== TEST 15: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.limit-count-multiple")
            local ok, err = plugin.check_schema({minute = 2, rejected_code = 503, key = 'remote_addr'})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 16: set key empty
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.limit-count-multiple")
            local ok, err = plugin.check_schema({minute = 2, rejected_code = 503})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- response_body
done



=== TEST 17: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count-multiple": {
                                "minute": 2,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 18: up the limit
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503, 503]



=== TEST 19: up the limit
--- pipelined_requests eval
["GET /hello1", "GET /hello", "GET /hello2", "GET /hello", "GET /hello"]
--- error_code eval
[404, 503, 404, 503, 503]



=== TEST 20: set route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count-multiple": {
                                "minute": 3,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 21: up the limit
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200, 503]



=== TEST 22: set route without id in post body
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-count-multiple": {
                                "minute": 1,
                                "rejected_code": 503,
                                "key": "remote_addr"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 23: up the limit
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 503, 503, 503]



=== TEST 24: disable plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 25: up the limit
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200, 200]



=== TEST 26: set route(key: server_addr)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count-multiple": {
                                "minute": 2,
                                "rejected_code": 503,
                                "key": "server_addr"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 27: up the limit
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503, 503]



=== TEST 28: default rejected_code
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count-multiple": {
                                "minute": 1,
                                "key": "remote_addr"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 29: create consumer and bind key-auth plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "consumer_jack",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-jack"
                        }
                    }
                }]]
                )
            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 30: create route and consumer_name is consumer_jack
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "key-auth": {},
                            "limit-count-multiple": {
                                "minute": 2,
                                "rejected_code": 503,
                                "key": "consumer_name"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 31: up the limit
--- more_headers
apikey: auth-jack
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503, 503]



=== TEST 32: set service(id: 1) and binding limit-count-multiple plugin
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                        "plugins": {
                            "limit-count-multiple": {
                                "minute": 2,
                                "rejected_code": 503,
                                "key": "service_id"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 33: set route(id: 1) and bind  service
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello",
                        "service_id": 1
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 34: the number of requests exceeds the limit
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503, 503]



=== TEST 35: set service(id: 1), and no limit-count-multiple plugin configured
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{}]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 36: set route(id: 1) and bind  service
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count-multiple": {
                                "minute": 2,
                                "rejected_code": 503,
                                "key": "service_id"
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello",
                        "service_id": 1
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 37: delete route(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1', ngx.HTTP_DELETE)

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 38: delete service(id: 1)
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1', ngx.HTTP_DELETE)

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 39: use 'remote_addr' as default key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                        "methods": ["GET"],
                        "plugins": {
                            "limit-count-multiple": {
                                "minute": 2,
                                "rejected_code": 503
                            }
                        },
                        "upstream": {
                            "nodes": {
                                "127.0.0.1:1980": 1
                            },
                            "type": "roundrobin"
                        },
                        "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 40: up the limit
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 503, 503]



=== TEST 41: add service and route, upstream is the domain name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/services/1',
                 ngx.HTTP_PUT,
                 [[{
                    "plugins": {
                        "limit-count-multiple": {
                            "minute": 3,
                            "rejected_code": 503
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "test.com:1980": 1,
                            "foo.com:1981": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
                ngx.say(body)
            end

            code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "uri": "/hello",
                    "service_id": 1
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 42: normal, the result is as expected
--- init_by_lua_block
    require "resty.core"
    apisix = require("apisix")
    core = require("apisix.core")
    apisix.http_init()

    local utils = require("apisix.core.utils")
    utils.dns_parse = function (domain)  -- mock: DNS parser
        if domain == "test.com" then
            return {address = "127.0.0.1"}
        end

        if domain == "foo.com" then
            return {address = "127.0.0.1"}
        end

        error("unknown domain: " .. domain)
    end
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200, 503, 503]



=== TEST 43: plugin is bound to the route and upstream is the domain name
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                 ngx.HTTP_PUT,
                 [[{
                    "methods": ["GET"],
                    "uri": "/hello",
                    "plugins": {
                        "limit-count-multiple": {
                            "minute": 3,
                            "rejected_code": 503
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "test.com:1980": 1,
                            "foo.com:1981": 1
                        },
                        "type": "roundrobin"
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- response_body
passed



=== TEST 44: normal, the result is as expected
--- init_by_lua_block
    require "resty.core"
    apisix = require("apisix")
    core = require("apisix.core")
    apisix.http_init()

    local utils = require("apisix.core.utils")
    utils.dns_parse = function (domain)  -- mock: DNS parser
        if domain == "test.com" then
            return {address = "127.0.0.1"}
        end

        if domain == "foo.com" then
            return {address = "127.0.0.1"}
        end

        error("unknown domain: " .. domain)
    end
--- pipelined_requests eval
["GET /hello", "GET /hello", "GET /hello", "GET /hello", "GET /hello"]
--- error_code eval
[200, 200, 200, 503, 503]
