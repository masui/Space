#!/usr/bin/env ruby
#
# 「space」(空間)コマンド
#
#  * あらゆる情報を放り込む
#
# Gyazoの認証手順
# https://gyazo.com/api/docs/auth
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

#
# gemのパスを全部 $: に加える
# require "bundler/setup" してGemfile.lockを読むというのが普通のようだが、bundlerが無いかもしれないので自力でやる
# 本当はgemspecのrequire_paths を見る必要があるようだが, libとgeneratedしか無いので
#
libdirs = `find #{appdir}/ruby | egrep '/(lib|generated)$'`
libdirs.split(/\n/).each { |dir|
  $: << dir
}

# 追加ライブラリ
require 'json'
require 'gyazo'
require 'exifr/jpeg'
require 'mime/types'

#
# AppleScriptでダイアログ表示
# dialog("メッセージ","OK",3)
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

#
# Gyazoの認証
#

#
# Gyazoの秘密トークン
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
    session.puts "Auth success"
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
    dialog("Gyazoアクセストークンが生成されました。","OK",3)
  end
end

def thumb(file,thumbnail)
  return unless File.exist?(file)
  
  tmpdir = "/tmp/universe_thumb"
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

def upload_gyazo(file, desc)
  log "upload_gyazo(#{file})"
  gyazo = Gyazo::Client.new access_token:gyazo_token

  log "gyazo_token = #{gyazo_token}"

  t = File.mtime(file)
  if file =~ /\.(jpg|jpeg)$/i  # JPEG
    log "upload #{file} to Gyazo..."
    begin
      exif = EXIFR::JPEG.new(file)
      t = exif.date_time if exif.date_time.to_s != ''
    rescue
    end
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
  log "gyazo_desc = #{desc}"
  return url
end

#
# Spaceのメインルーチン
#
def run
  log "Start Space"
  puts "Start space"

  # require 'config' # upload_cloud() の定義(など)

  check_gyazo_token

  if ARGV.length == 0
    puts "tantai"
    # 検索ページを開く
    # universe_search
  else # Drag&Drop
    puts "Drag&Drop--"
    filename = ''
    gyazo_url = ''
    cloud_url = ''
    ARGV.each { |file|
      puts "file = #{file}"
      filename = file
      puts filename
      #(gyazo_url, cloud_url) = upload_file file # クラウドにアップロード
      gyazo_url = upload_gyazo(filename,"DESC")

      log "upload #{file} => #{gyazo_url}"
    }

    # open_gyazo_or_scrapbox(gyazo_url,cloud_url,filename)
  end
end

def open_gyazo_or_scrapbox(gyazo_url,cloud_url,filename)
  system "open #{gyazo_url}"
end

run
