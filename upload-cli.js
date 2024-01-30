const env = require('./config.env.js');
const path = require('path')
const fs = require('node:fs/promises');
const commandLineArgs = require('command-line-args');

const generate_nginx_config = ()=>{
  return `
  events {
    worker_connections 1024;
  }

  pid logs/nginx.pid;
  
  http {
    error_log logs/error.log info;
    init_worker_by_lua_block {
      ngx.log(ngx.INFO, "UPLOADER DOING INIT 001")
      local uploadHandler = require("lua/upload")
      uploadHandler.startChecker() 
    }
    server {
      client_max_body_size 2048M;
      access_log logs/access.log combined;
      listen ${env.port};

      location /upload/upload {
        content_by_lua_block {
          local uploadHandler = require("lua/upload")
          uploadHandler.handleUpload()
        }
      }
  
      location ~ ^/upload/getfile/(?<id>[a-zA-Z0-9]+)$ {
        content_by_lua_block {
          local uploadHandler = require("lua/upload")
          uploadHandler.handleGetFile()
        }
      }

      location ~ ^/upload/getfileinfo/(?<id>[a-zA-Z0-9]+)$ {
        content_by_lua_block {
          local uploadHandler = require("lua/upload")
          uploadHandler.handleGetFileInfo()
        }
      }
    }
  }

  `

}

const main = async ()=>{
  const conf = generate_nginx_config();
  const optionDefinitions = [
    { name: 'print-only', type: Boolean, defaultOption: false },
  ]
  const options = commandLineArgs(optionDefinitions)
  const {"print-only":p} = options;
  if(p){
    console.log(conf)
    return
  }
  const tgt = path.resolve(__dirname, './conf/nginx.conf')
  await fs.writeFile(tgt, conf);
}

main()
