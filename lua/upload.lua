local cjson = require("cjson")
local UploadModule = {}
local chunk_size = 2048
-- 1. check whether has cached
-- 2. if so and offset larger than 0
-- 3. or open the file

local upload_meta_list = {
  -- key => len + offset + filename
  dummykey = {
    offset = 0,
    file_path = "temp/kkjude.js",
    file_name = "jude.js",
    resolved = true,
    created = 0, -- will be removed after in 2h once created
  }
}

local function check_upload_meta()
  local now = ngx.time()
  for key, item in pairs(upload_meta_list) do
    if (now - item.created > 2 * 60 * 60) then
      local success, err = os.remove(item.file_path)
      if not success then
        ngx.log(ngx.ERR, "fail to delete file" .. item.file_path)
      end
      upload_meta_list[key] = nil
    end
  end
end

local function remove_outdated_files()
  local command = "find ./temp -type f -mmin +120" -- finds files modified more than 120 minutes ago
  local handle = io.popen(command, "r")
  if handle then
    for file_path in handle:lines() do
      ngx.say(file_path)
      local ok, err = os.remove(file_path)
      if not ok then
        ngx.log(ngx.ERR, "Failed to remove file: ", file_path, " Error: ", err)
      end
    end
    handle:close()
  end
end

local function check_files()
  check_upload_meta()
  remove_outdated_files()
end


local allowed_origin = 'http://localhost:3000'
-- Function to set CORS headers
local function set_cors_headers()
  ngx.header["Access-Control-Allow-Origin"] = allowed_origin
  ngx.header["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
  ngx.header["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
  ngx.header["Access-Control-Allow-Credentials"] = "true"
end

local function extractInfoFromHeader(src)
  local namePattern = [[name="([^"]+)"]]
  local filenamePattern = [[filename="([^"]+)"]]

  local nameMatch = ngx.re.match(src, namePattern, "jo")
  local filenameMatch = ngx.re.match(src, filenamePattern, "jo")

  local name = nameMatch and nameMatch[1] or nil
  local filename = filenameMatch and filenameMatch[1] or nil
  return {
    name = name,
    filename = filename
  }
end

function UploadModule.hello()
  ngx.say('hey jude')
  ngx.exit(200)
end

function UploadModule.startChecker()
  ngx.timer.every(60*10, check_files)
end

function UploadModule.handleGetFileInfo()
  local theId = ngx.var.id
  local theItem = upload_meta_list[theId]
  if (not theItem) then
    -- ngx.say('item not found')
    ngx.exit(ngx.HTTP_NOT_FOUND)
    return
  end
  local bdy = {
    offset = theItem.offset,
    resolved = theItem.resolved
  }
  ngx.header["Content-Type"] = "application/json"
  ngx.say(cjson.encode(bdy))
  ngx.exit(ngx.HTTP_OK)
end

function UploadModule.handleGetFile()
  local theId = ngx.var.id
  local theItem = upload_meta_list[theId]
  if (not theItem) then
    -- ngx.say('item not found')
    ngx.exit(ngx.HTTP_NOT_FOUND)
    return
  end
  local resolved = theItem.resolved
  if (not resolved) then
    ngx.say('item is not resolved yet')
    ngx.exit(ngx.HTTP_BAD_REQUEST)
    return
  end
  ngx.log(ngx.INFO, "got meta as " .. cjson.encode(theItem))
  local file_path = theItem.file_path
  local file_name = theItem.file_name
  local file, err = io.open(file_path, "rb")
  if not file then
    ngx.say("file open err" .. err)
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    return
  end
  ngx.header["Content-Type"] = "application/octet-stream"
  ngx.header["Content-Disposition"] = 'attachment; filename="' .. file_name .. '"'
  ngx.send_headers()
  local chunk
  repeat
    chunk = file:read(1024)
    if chunk then
      ngx.print(chunk)
    end
  until not chunk
  file:close()
  ngx.eof()
end

function UploadModule.handleUpload()
  local upload = require "resty.upload"
  -- local method = ngx.req.get_method()
  set_cors_headers()
  if ngx.req.get_method() == "OPTIONS" then
    -- Respond to preflight requests with CORS headers
    ngx.exit(ngx.HTTP_OK)
    return
  end
  local form, err = upload:new(chunk_size)
  if not form then
    ngx.log(ngx.ERR, "failed to new upload: ", err)
    ngx.exit(500)
    return
  end
  local upload_key = nil
  local file_name = nil
  local the_file = nil   --file handler
  local the_offset = nil --offset for seek
  local upload_meta = nil
  local local_file_path = nil
  while true do
    local type, res, err = form:read()
    if not type then
      ngx.say("failed to read:", err)
      ngx.exit(500)
      return
    end
    if type == "header" then
      local header_name, header_val = res[1], res[2]
      if (header_name == "Content-Disposition") then
        local m = extractInfoFromHeader(header_val)
        local file_name_from_info = m.filename
        local key_from_info = m.name
        if (not file_name_from_info or not key_from_info) then
          ngx.say("fail to read the filename and key ==> ", header_val, header_name)
          ngx.exit(500)
          return
        end
        file_name = file_name_from_info
        upload_key = key_from_info
        if (upload_meta_list[upload_key]) then
          upload_meta = upload_meta_list[upload_key]
          the_offset = upload_meta.offset
          local_file_path = upload_meta.file_path
          local the_file_1, err = io.open(local_file_path, "r+b");
          if (not the_file_1) then
            upload_meta_list[upload_meta_list] = nil
            ngx.say("fail to open file with r+b", upload_meta.file_path, err)
            ngx.exit(500)
            return
          end
          the_file = the_file_1
          the_file:seek("set", the_offset);
        else
          local_file_path = "temp/" .. upload_key .. file_name
          upload_meta = {
            offset = 0,
            file_path = local_file_path,
            file_name = file_name,
            resolved = false,
            created = ngx.time(),
          }
          upload_meta_list[upload_key] = upload_meta
          the_file = io.open(local_file_path, "w+")
          the_offset = 0;
        end
      end
    elseif type == "body" then
      if (not upload_meta or not the_file) then
        ngx.say("not prepared for reading file body")
        ngx.exit(500)
        return
      end
      local len = string.len(res)
      local _, err = the_file:write(res)
      if (err) then
        ngx.say("got err when writing file as " .. err)
        ngx.exit(500)
        return
      end
      ngx.log(ngx.INFO, len, ' Bytes WRITTEN')
      upload_meta.offset = upload_meta.offset + len
    elseif type == "part_end" then
      if (not upload_meta or not the_file) then
        ngx.say("not prepared for reading file body")
        ngx.exit(500)
        return
      end
      upload_meta.resolved = true
      ngx.log(ngx.INFO, file_name .. ' finished')
      the_file:close()
      the_file = nil
      upload_meta = nil
    elseif type == "eof" then
      ngx.log(ngx.INFO, 'WRITING SUCCESS 2')
      local response = {
        success = true,
        message = "File uploaded successfully.",
      }
      ngx.header["Content-Type"] = "application/json"
      ngx.say(cjson.encode(response))
      ngx.exit(ngx.HTTP_OK)
      break
    else
    end
  end
end

return UploadModule
