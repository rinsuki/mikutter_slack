# -*- coding: utf-8 -*-
require 'slack'
require 'uri'
require 'cgi'
require 'json'
require 'httpclient'
require 'webrick'
require_relative '../environment'

module Plugin::Slack
  module API
    class Auth

      # TODO: 認証を開発者トークンとOAuthのどちらでもできるようにする
      # バカにしか見えない…バカにしか見えない…バカにしか見えない…
      @client_id = Plugin::Slack::Environment::SLACK_CLIENT_ID
      @client_secret = Plugin::Slack::Environment::SLACK_CLIENT_SECRET
      @redirect_uri = Plugin::Slack::Environment::SLACK_REDIRECT_URI

      def initialize(client)
        @client = client
      end


      # ここから先はな…
      # 黒魔術なんじゃあびゃああああああ
      # OAuthライブラリがあるのにな…
      # 使い方がよくわからんかったからWebRickでゴリ押しンギモチィィ⤴︎⤴︎

      # OAuth認証を行う
      # @return [Delayer::Deferred::Deferredable] なんかを引数にcallbackするDeferred
      # @see {https://api.slack.com/docs/oauth}
      def self.oauth
        Thread.new {
          client = HTTPClient.new
          query = {client_id: @client_id, scope: 'client', redirect_uri: @redirect_uri, state: 'mikutter_slack'}.to_hash
          client.get('https://slack.com/oauth/authorize', :query => query, 'Content-Type' => 'application/json')
        }.next { |response|
          Delayer::Deferred.fail(response) unless (response.status_code == 302)
          # OAuth認証用ページへのリダイレクトURL
          oauth_redirect_uri = response.header['location'][0]
          Plugin.call(:open, "https://slack.com#{URI.decode(oauth_redirect_uri)}")
          Thread.new {
            config = {
                :DocumentRoot => File.join(__dir__, '../www/'),
                :BindAddress => 'localhost',
                :Port => 8080
            }
            @server = WEBrick::HTTPServer.new(config)
            @server.mount_proc('/') do |_, res|
              Delayer::Deferred.fail(res) unless res.status == 200

              # TODO: res.request_uri を持たない場合に対応する（favicon.icoの要求）
              # FIXME: webrickをshutdownするタイミングを修正する
              query = CGI.parse(res.request_uri.query)
              # ローカルのHTMLを表示
              res.body = open(File.join(__dir__, '../www/', 'index.html'))
              # アクセストークンの取得
              self.oauth_access(query['code'][0]).next { |_token|
                @server.shutdown
              }.trap { |e| error e }
            end
            trap('INT') { @server.shutdown }
            @server.start
          }.trap { |e|
            error e
            @server.shutdown
          }
        }
      end


      # 認証テスト
      # @return [Delayer::Deferred::Deferredable] 認証結果を引数にcallbackするDeferred
      def auth_test
        Thread.new { @client.auth_test }
      end


      private


      # OAuthのコールバックで得たcodeを用いてaccess_tokenを取得する
      # @param [String] code コールバックコード
      # @return [Delayer::Deferred::Deferredable] access_tokenを引数にcallbackするDeferred
      # @see {https://api.slack.com/methods/oauth.access}
      def self.oauth_access(code)
        Thread.new(code) { |c|
          client = HTTPClient.new
          query = {
              client_id: @client_id,
              client_secret: @client_secret,
              code: c,
              redirect_uri: @redirect_uri
          }.to_hash
          client.get('https://slack.com/api/oauth.access', :query => query, 'Content-Type' => 'application/json')
        }.next { |res|
          Delayer::Deferred.fail(res) unless res.status_code == 200
          body = JSON.parse(res.body, symbolize_names: true)
          Delayer::Deferred.fail(body[:error]) unless body[:ok]
          notice "scope: #{body[:scope]}, user_id: #{body[:user_id]}, team_name: #{body[:team_name]}, team_id: #{body[:team_id]}"
          notice "token: #{body[:access_token]}"
          UserConfig['slack_token'] = body[:access_token]
        }
      end

    end
  end
end
