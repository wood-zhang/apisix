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
use t::APISIX 'no_plan';

log_level('warn');
repeat_each(1);
no_long_string();
no_root_location();

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
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "desc": "new route",
                    "uri": "/hello"
                }]]
            )

            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]
--- SKIP



=== TEST 2: enable prometheus in global rules
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/global_rules/1',
                ngx.HTTP_PUT,
                [[{
                "plugins": {
                    "prometheus": {}
                }
            }]]
            )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]
--- SKIP



=== TEST 3: hit route 1
--- request
GET /hello
--- response_body_like
hello world
--- wait: 1
--- no_error_log
[error]
--- SKIP



=== TEST 4: set route 2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello2"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 5: hit route 2
--- request
GET /hello2
--- error_code: 503
--- no_error_log
[error]
--- LAST



=== TEST 6: set ssl(sni: test.com)
--- config
location /t {
    content_by_lua_block {
        local core = require("apisix.core")
        local t = require("lib.test_admin")

        local ssl_cert = t.read_file("t/certs/apisix.crt")
        local ssl_key =  t.read_file("t/certs/apisix.key")
        local data = {cert = ssl_cert, key = ssl_key, sni = "test.com"}

        local code, body = t.test('/apisix/admin/ssl/1',
            ngx.HTTP_PUT,
            core.json.encode(data)
            )

        if code >= 300 then
            ngx.status = code
        end
        ngx.say(body)
    }
}
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 7: set route 2
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/2',
                 ngx.HTTP_PUT,
                 [[{
                    "upstream": {
                        "nodes": {
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello2"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 7: hit route 2
--- request
GET /hello2
--- error_code: 503
--- no_error_log
[error]
--- LAST



=== TEST 6: hit route 1
--- request
GET /hello
--- error_code: 200



=== TEST 6: hit route 1 and route 2 together
--- pipelined_requests eval
[
    "GET /hello2?a=b", "GET /hello?a=c", "GET /hello2?a=d",
    "GET /hello2?a=b", "GET /hello?a=c", "GET /hello2?a=d",
    "GET /hello2?a=b", "GET /hello?a=c", "GET /hello2?a=d",
    "GET /hello2?a=b", "GET /hello?a=c", "GET /hello2?a=d",
    "GET /hello2?a=b", "GET /hello?a=c", "GET /hello2?a=d",

]
--- error_code eval
[
    503, 200, 503,
    503, 200, 503,
    503, 200, 503,
    503, 200, 503,
    503, 200, 503,

]
--- wait: 1
--- LAST



=== TEST 7: hit route 1 and route 2 together
--- pipelined_requests eval
[
    "GET /hello2", "GET /hello", "GET /hello2",
]
--- error_code eval
[
    503, 200, 503,
]
--- wait: 1
