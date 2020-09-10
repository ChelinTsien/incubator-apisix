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

repeat_each(2);
no_long_string();
no_root_location();
no_shuffle();
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.aksk-auth")
            local conf = {}

            local ok, err = plugin.check_schema(conf)
            if not ok then
                ngx.say(err)
            end

            ngx.say(require("cjson").encode(conf))
        }
    }
--- request
GET /t
--- response_body_like eval
qr/{"version":"apisix","service_name":"apisix","region":"","secret_key":"[a-zA-Z0-9+\\\/]+={0,2}","expire_time":600,"signed_headers":["host","content-type","x-amz-date"],"access_key":"[a-zA-Z0-9+\\\/]+={0,2}"}/
--- no_error_log
[error]



=== TEST 2: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local plugin = require("apisix.plugins.aksk-auth")
            local ok, err = plugin.check_schema({access_key = 123})
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "key" validation failed: wrong type: expected string, got number
done
--- no_error_log
[error]



=== TEST 3: add consumer with username and plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "aksk",
                    "plugins": {
                        "aksk-auth": {
                            "access_key": "test_user_ak",
                            "secret_key": "test_user_sk"
                        }
                    }
                }]],
                [[{
                    "node": {
                        "value": {
                            "username": "aksk",
                            "plugins": {
                                "aksk-auth": {
                                    "access_key": "test_user_ak",
                                    "secret_key": "test_user_sk"
                                }
                            }
                        }
                    },
                    "action": "set"
                }]]
                )

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 4: enable aksk auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "aksk-auth": {}
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
--- request
GET /t
--- response_body
passed
--- no_error_log
[error]



=== TEST 5: verify, missing auth headers
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"header 'x-amz-date' is needed"}
--- no_error_log
[error]



=== TEST 6: verify: signature expired
--- request
GET /hello
--- more_headers
Authorization: APISIX-HMAC-SHA256 Credential=test_user_ak/20200910/cn1/apisix/apisix_request, SignedHeaders=host;x-amz-date, Signature=95183f01b01ebe8e051c41b58dc62fc2011a87493026a112e55632dbb4f6f0ab
x-amz-date: 20200910T063231Z
--- error_code: 401
--- response_body
{"message":"signature expireed"}
--- no_error_log
[error]



=== TEST 7: verify (invalid Authorization)
--- request
GET /hello
--- more_headers
Authorization: test
--- error_code: 401
--- response_body
{"message":"invalid authorization"}
--- no_error_log
[error]



=== TEST 8: valid consumer
--- request
GET /hello
--- more_headers
Authorization: APISIX-HMAC-SHA256 Credential=test_user_ak/20200910/cn1/apisix/apisix_request, SignedHeaders=host;x-amz-date, Signature=95183f01b01ebe8e051c41b58dc62fc2011a87493026a112e55632dbb4f6f0ab
x-amz-date: 20200910T063231Z
--- response_body
hello world
--- no_error_log
[error]



=== TEST 9: invalid consumer
--- request
GET /hello
--- more_headers
Authorization: APISIX-HMAC-SHA256 Credential=test_user_ak/20200910/cn1/apisix/apisix_request, SignedHeaders=host;x-amz-date, Signature=95183f01b01ebe8e051c41b58dc62fc2011a87493026a112e55632dbb4f6f0ab
x-amz-date: 20200910T063231Z
--- error_code: 401
--- response_body
{"message":"Invalid access_key"}
--- no_error_log
[error]