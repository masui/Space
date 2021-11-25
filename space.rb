#!/usr/bin/env ruby
#
# 「space」(空間)コマンド
#
#  * あらゆる情報を放り込む
#
#  * Gyazoの認証手順
#    https://gyazo.com/api/docs/auth
#  * GoogleDriveの認証手順
#

# ローカルのgemを利用する方法
#
#  1. 以下のようなGemfileを作る
#  # frozen_string_literal: true
#  
#  source "https://rubygems.org"
#  
#  git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }
#  
#  gem 'gyazo'
#  ...
# 
#  2.
#  bundle install --path .
# 
#  とすると ./ruby/... にgemが入る
# 
#  3. $: にgemのパスを足す
#

# アプリのディレクトリをrubyのパスに追加
appdir = File.dirname(__FILE__)
$: << appdir

# 標準ライブラリ
require 'net/http'
require 'uri'
require 'json'
require 'socket'
require 'find'

#
# gemのパスを全部 $: に加える
# require "bundler/setup" してGemfile.lockを読むというのが普通のようだが、bundlerが無いかもしれないので自力でやる
# 本当はgemspecのrequire_paths を見る必要があるようだが, libとgeneratedしか無いので
#
#libdirs = `find #{appdir}/ruby | egrep '/(lib|generated)$'`
#libdirs.split(/\n/).each { |dir|
#  $: << dir
#}

# 追加ライブラリ
require 'json'
require 'gyazo'
require 'exifr/jpeg'
require 'mime/types'

#
# ダイアログ表示 dialog("メッセージ","OK",3)
# AppleScriptを利用
#
def dialog(message, button, timeout=3)
  if button.class == Array
    buttons = button.collect { |button|
      '"' + button + '"'
    }.join(", ")
    log buttons
    `osascript -e 'display dialog "#{message}" buttons { #{buttons} } giving up after #{timeout}'`
  else
    `osascript -e 'display dialog "#{message}" buttons {"#{button}"} giving up after #{timeout}'`
  end
end

# ログをセーブ
def log(message)
  logdir = File.expand_path("~/Library/Logs/Space") # これが標準のログファイルの場所らしい
  Dir.mkdir(logdir) unless File.exist?(logdir)
  logfile = "#{logdir}/space.log"
  File.open(logfile,"a"){ |f|
    f.puts "[#{Time.now}] #{message}"
  }
end

def app_dir
  File.dirname(__FILE__)
end

# qlmanageでサムネイルを作る
def thumb(file,thumbnail)
  return unless File.exist?(file)
  
  tmpdir = "/tmp/space_thumb"
  Dir.mkdir(tmpdir) unless File.exist?(tmpdir)

  qlcmd = "/usr/bin/qlmanage -t '#{file}' -s 1024 -x -o #{tmpdir}"
  pngpath = "#{tmpdir}/#{File.basename(file)}.png"

  log qlcmd
  system qlcmd

  if File.exist?(pngpath)
    log "qlmanageでサムネ作成成功"
  else
    log "qlmanageでサムネ作成失敗"
    tmphtml = "#{tmpdir}/thumb.html"
    File.open(tmphtml,"w"){ |f|
      f.puts thumb_html(file)
    }
    qlcmd = "/usr/bin/qlmanage -t #{tmphtml} -s 512 -x -o #{tmpdir}"
    pngpath = "#{tmpdir}/thumb.html.png"

    log qlcmd
    system qlcmd
  end

  if File.exist?(pngpath)
    system "/bin/cp '#{pngpath}' #{thumbnail}"
    Dir.new(tmpdir).each { |file|
      File.delete("#{tmpdir}/#{file}") if file !~ /^\./
    }
  else
    log "#{pngpath}作成失敗"
    exit
  end
end

#
# Gyazoの認証とアップロード
#
# Gyazoの秘密トークン処理
#
def gyazo_token_path
  "#{app_dir}/gyazo_token"
end

def set_gyazo_token(token)
  if File.exist?(app_dir)
    File.open(gyazo_token_path,"w"){ |f|
      f.puts token
    }
  end
end
  
def gyazo_token
  if File.exist?(gyazo_token_path)
    return File.read(gyazo_token_path).chomp
  end
  return nil
end

#
# Gyazoのアクセストークン取得
#
def check_gyazo_token
  gyazo_client_id = "USECCHCZuVIN3DykF7Ixvy_wR93NqoUWlcMkQK2EoYM"     # Space.app用のID
  gyazo_client_secret = "7qcQynnsvWh_AZ78Lp-ZCvPkADG48ZH6jHsKcBpM0t0"
  gyazo_callback_url = "http://localhost/"

  if !gyazo_token
    dialog("Gyazoアクセストークンを生成するため認証してください","OK",3)
    cmd = "https://gyazo.com/oauth/authorize?client_id=#{gyazo_client_id}&redirect_uri=#{gyazo_callback_url}&response_type=code"
    puts "open '#{cmd}'"
    system "open '#{cmd}'"
    
    # 簡易(?)HTTPサーバをたてる
    server = TCPServer.new 80
    session = server.accept
    request = session.gets
    method, full_path = request.split(' ')
    session.puts "Gyazo auth success"
    session.close
    server.close
    
    full_path.sub!(/\/\?/,'')
    full_path.sub!(/\s+.*$/,'')
    gyazo_auth_code = ''
    full_path.split(/&/).each { |s|
      a = s.split(/=/)
      if a[0] == 'code'
        gyazo_auth_code = a[1]
      end
    }
    # 認証のためのcodeが取得される
    puts "auth code = #{gyazo_auth_code}"
    
    #
    # Gyazoのアクセストークンを取得
    #
    uri = URI.parse("https://gyazo.com/oauth/token")
    req = Net::HTTP::Post.new(uri)
    req.set_form_data({
                        'code' => gyazo_auth_code,
                        'client_id' => gyazo_client_id,
                        'client_secret' => gyazo_client_secret,
                        'redirect_uri' => gyazo_callback_url,
                        'grant_type' => 'authorization_code'
                      })
    req_options = {
      use_ssl: true
    }
    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(req)
    end
    puts "response.body = #{response.body}"
    set_gyazo_token JSON.parse(response.body)['access_token'] # responseはJSONで返る
    dialog("Gyazoアクセストークンが生成されました。","OK",2)
    log "gyazo_token = #{gyazo_token}"
  end
end

def upload_gyazo(file, desc, t)
  log "upload_gyazo(#{file})"

  check_gyazo_token

  gyazo = Gyazo::Client.new access_token:gyazo_token

  res = ''
  # t = File.mtime(file)
  if file =~ /\.(jpg|jpeg)$/i  # JPEG
    log "upload #{file} to Gyazo..."
    #begin
    #  exif = EXIFR::JPEG.new(file)
    #  t = exif.date_time if exif.date_time.to_s != ''
    #rescue
    #end
    res = gyazo.upload imagefile: file, created_at: t, desc: desc
  elsif file =~ /\.(gif|png)$/i # その他の画像
    log "upload #{file} to Gyazo..."
    res = gyazo.upload imagefile: file, created_at: t, desc: desc
  else
    thumbimage = "/tmp/thumb.png"
    thumb(file,thumbimage)
    log "upload #{file} to Gyazo... thumb = #{thumbimage}"
    res = gyazo.upload imagefile: thumbimage, created_at: t, desc: desc
  end
  sleep 1
  url = res[:permalink_url]
  log "gyazo_url = #{url}"
  return url
end

#
# GoogleDriveの認証とアップロード
#
require 'google/apis/drive_v3'
require 'google/api_client/client_secrets'

#
# Googleの秘密トークン
#
def google_refresh_token_path
  "#{app_dir}/google_refresh_token"
end

def set_google_refresh_token(token)
  if File.exist?(app_dir)
    File.open(google_refresh_token_path,"w"){ |f|
      f.puts token
    }
  end
end
  
def google_refresh_token
  if File.exist?(google_refresh_token_path)
    return File.read(google_refresh_token_path).chomp
  end
  return nil
end

def googledrive_service
  # OAuthで使うclient_idとclient_secret
  # client_secrets = Google::APIClient::ClientSecrets.load とすると client_secrets.json を読むのだが
  # 別ファイルにするのも面倒なので直書きしている
  # これらは'secret'と書いてあるが、アプリケーションを同定するためのものであり、ユーザの認証情報ではない
  google_secret_data = {
    installed: {
      client_id: "245084284632-v88q7r65ddine8aa94qp7ribop4018eg.apps.googleusercontent.com",
      client_secret: "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"
    }
  }
  client_secrets = Google::APIClient::ClientSecrets.new google_secret_data
  log "Google_client_secrets = #{client_secrets}"
    
  auth_client = client_secrets.to_authorization
  log "auth_client = #{auth_client}"
    
  auth_client.update!(
    :scope => 'https://www.googleapis.com/auth/drive', # 全部許可
    :redirect_uri => "http://localhost/"               # localhostへのコールバック
  )
    
  if google_refresh_token
    # 既存のrefresh_tokenを使う
    auth_client.refresh_token = google_refresh_token
  else
    dialog("GoogleDriveのアクセストークンを生成するため認証してください","OK",3)

    auth_uri = auth_client.authorization_uri.to_s
    system "open '#{auth_uri}'"
      
    # 簡易(?)HTTPサーバをたてる
    server = TCPServer.new 80
    session = server.accept
    request = session.gets
    method, full_path = request.split(' ')
    session.puts "GoogleDrive auth success"
    session.close
    server.close

    full_path = URI.decode(full_path)
    full_path.sub!(/\/\?/,'')
    full_path.sub!(/\s+.*$/,'')
    code = ''
    full_path.split(/&/).each { |s|
      a = s.split(/=/)
      if a[0] == 'code'
        code = a[1]
      end
    }
    # 認証のためのcodeが取得される
    log "google auth code = #{code}"
      
    auth_client.code = code
    auth_client.fetch_access_token!
    puts "auth_client.refresh_token = #{auth_client.refresh_token}"
    
    set_google_refresh_token(auth_client.refresh_token)# トークンをセーブ
    log "Google refresh_token = #{google_refresh_token}"
    dialog("GoogleDriveのアクセストークンが生成されました。","OK",2)
    
  end
    
  drive_service = Google::Apis::DriveV3::DriveService.new
  drive_service.authorization = auth_client

  return drive_service
end

def upload_googledrive(file)
  File.open("/tmp/error","a"){ |f|
    f.puts "upload_googledrive(#{file})"
  }
  log "upload_googledrive #{file}"
  drive_service = googledrive_service
  log "drive_service = #{drive_service}"

  response = drive_service.list_files(q: "name = 'Space' and mimeType = 'application/vnd.google-apps.folder' and parents in 'root'", fields: "files(id, name, parents)")
  
  if response.files.empty? # Spaceフォルダが存在しない場合
    # "Space" フォルダ生成
    file_metadata = {
      name: 'Space',
      mime_type: 'application/vnd.google-apps.folder'
    }
    res = drive_service.create_file(file_metadata, fields: 'id')
    response = drive_service.list_files(q: "name = 'Space' and mimeType = 'application/vnd.google-apps.folder'", fields: "files(id, name)")
  end

  File.open("/tmp/error","a"){ |f|
    f.puts file
  }
  
  #
  # Spaceフォルダにファイルを作成
  #
  
  mimetype = MIME::Types.type_for(file)[0].to_s
  
  file = file.force_encoding("UTF-8") # こうしないとGoogleDriveにアップロードできない
  
  filename = File.basename(file)
  
  folder_id = response.files[0].id
  file_object = {
    name: filename,
    parents: [folder_id]
  }
  File.open("/tmp/error","a"){ |f|
    f.puts "try copy"
  }
  if false
    system "/bin/cp '#{file}' /tmp/xxxx"
    begin
      res = drive_service.create_file(file_object, {upload_source:"/tmp/xxxx", content_type: mimetype})
    rescue => e
      File.open("/tmp/error","a"){ |f|
        f.puts e
      }
    end
  end
  res = drive_service.create_file(file_object, {upload_source:file, content_type: mimetype})

  File.open("/tmp/error","a"){ |f|
    f.puts "copy success"
  }
  dialog("GoogleDriveのSpaceフォルダに#{file}が保存されました。","OK",2)
  "https://drive.google.com/open?id=#{res.id}"
end

#
# S3へのアップロード (ほぼ増井専用)
# ~/.space に書いておく
#
def upload_s3(file,bucket)
  ext = ''
  if file =~ /^(.*)(\.\w+)$/ then
    ext = $2
  end
  hash = Digest::MD5.file(file).to_s

  begin
    # aws cp コマンドを使う
    # 認証情報は ~/.aws/ にある
    # ファイル名が日本語だとうまくいかないことがあるので別ファイルにコピーしてからアップロード
    dstfile = "s3://#{bucket}/#{hash[0]}/#{hash[1]}/#{hash}#{ext}"
    system "/bin/cp '#{file}' /tmp/__space_file"
    system "/usr/local/bin/aws s3 cp --profile default /tmp/__space_file #{dstfile} --acl public-read "
    system "/bin/rm /tmp/__space_file"
    "https://s3-ap-northeast-1.amazonaws.com/#{bucket}/#{hash[0]}/#{hash[1]}/#{hash}#{ext}"
  rescue => e
    File.open("/tmp/error","a"){ |f|
      f.puts e
    }
  end
  "https://s3-ap-northeast-1.amazonaws.com/#{bucket}/#{hash[0]}/#{hash[1]}/#{hash}#{ext}"
end


#
# Spaceのメインルーチン
#
def run
  log "Start Space"
  puts "Start space"

  # require 'config' # upload_cloud() の定義(など)

  # ????.app のアプリ名を取得
  project = "Space"
  path = $0
  if path =~ /\/([a-zA-Z\-\.]+)\.app\//
    project = $1
  end

  puts project
    
  if ARGV.length == 0
    system "open https://scrapbox.io/#{project}"
  else # Drag&Drop
    allfiles = [] # セーブするファイル全部
    allitems = [] # 指定されたファイルとフォルダ

    ARGV.each { |item|
      if File.exist?(item)
        allitems.push(item)
        if File.directory?(item)
          puts "file <#{item}> is directory"
        end
        Find.find(item) { |f|
          if File.file?(f)
            allfiles.push f
          end
        }
      end
    }

    attrs = []
    allfiles.each { |file|
      attr = {}
      attr['filename'] = file
      attr['fullname'] = File.expand_path(file)
      attr['basename'] = File.basename(file)

      # MD5値
      attr['md5'] = Digest::MD5.file(file).to_s

      # 時刻
      #attr['time'] = modtime(file)
      attr['time'] = File.mtime(file)
      if file =~ /(\w+)\.(jpg|jpeg)/i
        begin
          exif = EXIFR::JPEG.new(file)
          t = exif.date_time
          if t
            attr['time'] = t
          end
        rescue
        end
      end
      attr['time14'] = attr['time'].strftime("%Y%m%d%H%M%S")

      # サイズ
      attr['size'] = File.size(file)

      # Gyazoにアップロード
      # qlmanageでサムネイル作成
      qlcmd = "/usr/bin/qlmanage -t '#{attr['fullname']}' -s 1024 -x -o /tmp"
      pngpath = "/tmp/#{attr['basename']}.png"

      File.open("/tmp/log","w"){ |f|
        f.puts qlcmd
        f.puts pngpath
      }
      system qlcmd
      if File.exist?(pngpath)
        STDERR.puts "upload #{pngpath} to Gyazo..."
        File.open("/tmp/log","a"){ |f|
          f.puts "upload #{pngpath} to Gyazo..."
        }
        gyazourl = upload_gyazo(pngpath, "DESC", attr['time'])
        # res = @gyazo.upload imagefile: pngpath, created_at: attr['time']

        system "/bin/rm '#{pngpath}'"
        # gyazourl = res[:permalink_url]
        attr['gyazourl'] = gyazourl
      end
    
      # GPS情報
      if file =~ /\.(jpg|jpeg)$/i
        begin
          exif = EXIFR::JPEG.new(file)
          d = exif.gps_longitude
          if d
            long = d[0] + d[1] / 60 + d[2] / 3600
            d = exif.gps_latitude
            lat = d[0] + d[1] / 60 + d[2] / 3600
            mapline = "[#{exif.gps_latitude_ref}#{lat.to_f},#{exif.gps_longitude_ref}#{long.to_f},Z14]"
            attr['mapline'] = mapline
          end
        rescue
        end
      end

      # テキストデータ
      File.open("/tmp/error","w"){ |f|
        f.puts attr['fullname']
        f.puts "/usr/bin/file '#{attr['fullname']}'"
      }
      begin
        s = `LANG=ja_JP.UTF-8 /usr/bin/file '#{attr['fullname']}'`.force_encoding("UTF-8")
        File.open("/tmp/error","a"){ |f|
          f.puts s
        }
        
        if `LANG=ja_JP.UTF-8 /usr/bin/file '#{attr['fullname']}'`.force_encoding("UTF-8") =~ /text/
          File.open("/tmp/error","a"){ |f|
            f.puts "This is a text file."
          }
          text = File.read(attr['fullname']).force_encoding("UTF-8")
          texts = text.split(/\n/)[0,10]
          if text.length > 900
            texts = text.split(/\n/)[0,2]
          end
          File.open("/tmp/error","a"){ |f|
            f.puts text
          }
          attr['text'] = texts
        end
      rescue => e
        File.open("/tmp/error","a"){ |f|
          f.puts e
        }
      end

      File.open("/tmp/space","w"){ |f|
        f.puts attr
      }

      s3bucket = nil
      space_cfg = File.expand_path("~/.space")
      if File.exist?(space_cfg)
        begin
          data = JSON.parse(File.read(space_cfg))
          if data['s3-bucket']
            s3bucket = data['s3-bucket']
          end
        rescue
        end
      end
      if s3bucket
        File.open("/tmp/error","a"){ |f|
          f.puts file
        }
        attr['uploadurl'] = upload_s3(file,s3bucket)
      else
        File.open("/tmp/error","a"){ |f|
          f.puts "xxxxx #{file}"
        }
        attr['uploadurl'] = upload_googledrive(file)
      end

      File.open("/tmp/error","a"){ |f|
        f.puts "s3 upload success"
        f.puts "file = #{attr['uploadurl']}"
      }
      
      attrs.push(attr)
    }
    
    # Scrapboxテキスト作成
    begin    
      str = ''.force_encoding("UTF-8")
      attrs.each { |attr|
        obj = {}
        str += "[#{attr['fullname']} #{attr['uploadurl']}]\n".force_encoding("UTF-8")
        if attr['text']
          attr['text'].each { |line|
            str += ">#{line}\n".force_encoding("UTF-8")
          }
        end
        if attr['time14']
          attr['time14'] =~ /^(........)(.*)$/
          s = "[#{$1}]#{$2}"
          str += "Date: #{s}\n".force_encoding("UTF-8")
        end
        str += "#{attr['mapline']}\n".force_encoding("UTF-8") if attr['mapline']
        str += "File: [#{attr['basename']}]\n".force_encoding("UTF-8") # 同じファイル名のものをリンクするため
        str += "Size: #{attr['size']}\n".force_encoding("UTF-8") if attr['size']
        str += "[[#{attr['gyazourl']} #{attr['uploadurl']}]]\n".force_encoding("UTF-8") if attr['gyazourl']
        str += "\n".force_encoding("UTF-8")
      }
    rescue => e
      File.open("/tmp/error","a"){ |f|
        f.puts e
      }
    end

    # ゴミ箱へ
    puts "allitems = #{@allitems}"
    allitems.each { |item|
      path = File.expand_path(item)
      next unless File.exist?(path)
      script = <<EOF
tell application "Finder"
  move POSIX file "#{path}" to trash
end tell
EOF
      # 消さなくてもいいかも
      # system "/usr/bin/osascript -e '#{script}'"
    }

    # Scrapboxページ開く
    datestr = Time.now.strftime('%Y%m%d%H%M%S')
    system "/usr/bin/open 'https://Scrapbox.io/#{project}/#{datestr}?body=#{URI.encode_www_form_component(str)}'"
  end
end

run
