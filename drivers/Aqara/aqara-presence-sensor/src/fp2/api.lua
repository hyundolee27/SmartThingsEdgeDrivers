local log = require "log"
local json = require "st.json"
local RestClient = require "lunchbox.rest"
local utils = require "utils"
local st_utils = require "st.utils"

local fp2_api = {}
fp2_api.__index = fp2_api

local SSL_CONFIG = {
  mode = "client",
  protocol = "any",
  verify = "peer",
  options = "all",
  cafile = "./selfSignedRootByAqaraLife.crt"
}

local ADDITIONAL_HEADERS = {
  ["Accept"] = "application/json",
  ["Content-Type"] = "application/json",
}

function fp2_api.labeled_socket_builder(label)
  local socket_builder = utils.labeled_socket_builder(label, SSL_CONFIG)
  return socket_builder
end

local function get_base_url(device_ip)
  return "https://" .. device_ip .. ":443"
end

local function process_rest_response(response, err, partial)
  if err ~= nil then
    return response, err, nil
  elseif response ~= nil then
    local _, decoded_json = pcall(json.decode, response:get_body())
    return decoded_json, nil, response.status
  else
    return nil, "no response or error received", nil
  end
end

local function do_get(api_instance, path)
  return process_rest_response(RestClient.one_shot_get(api_instance.base_url .. path, api_instance.headers, api_instance.socket_builder))
end

function fp2_api.new_device_manager(device_ip, bridge_info, socket_builder)
  local base_url = get_base_url(device_ip)

  return setmetatable(
    {
      headers = st_utils.deep_copy(ADDITIONAL_HEADERS),
      socket_builder = socket_builder,
      base_url = base_url,
    }, fp2_api
  )
end

function fp2_api:add_header(key, value)
  self.headers[key] = value
end

local function retry_fn(retry_attempts)
  local count = 0
  return function()
    count = count + 1
    return count < retry_attempts
  end
end

function fp2_api.get_register_info(device_ip, socket_builder)
  local client = RestClient.new(get_base_url(device_ip), socket_builder)
  local register_info = {
    info = nil,
    token = nil,
  }

  local response, error, status = process_rest_response(
    client:get(get_base_url(device_ip) .. "/info",
    ADDITIONAL_HEADERS,
    retry_fn(5)))

  if (not response) or error or (status ~= 200) then
    log.error(string.format("get_register_info : ip = %s, failed to get info, error = %s", device_ip, error))
    client:close_socket()
    return nil, error, status
  end
  register_info.info = response

  response, error, status = process_rest_response(
    client:get(get_base_url(device_ip) .. "/authcode",
    ADDITIONAL_HEADERS,
    retry_fn(5)))

  if (not response) or error or (status ~= 200) then
    log.error(string.format("get_register_info : ip = %s, failed to get authcode, error = %s", device_ip, error))
    client:close_socket()
    return nil, error, status
  end
  register_info.token = response

  client:close_socket()

  return register_info
end

function fp2_api.get_info(device_ip, socket_builder)
  return process_rest_response(RestClient.one_shot_get(get_base_url(device_ip) .. "/info", ADDITIONAL_HEADERS,
    socket_builder))
end

function fp2_api:get_attr()
  return do_get(self, "/attr")
end

function fp2_api:get_remove()
  return do_get(self, "/remove")
end

function fp2_api:get_sse_url()
  return self.base_url .. "/status"
end

return fp2_api
