# -*- coding: utf-8 -*-
require 'net/https'
require 'uri'
require 'json'
require File.expand_path(File.join(File.dirname(__FILE__), "utils"))
require File.expand_path(File.join(File.dirname(__FILE__), "installer"))

class Gist
    def initialize(id, gist)
        @id = id
        @gist = gist
    end

    def [](key)
        @gist[key]
    end

    def codes
        @gist["files"].select do |key, val|
            File.extname(key) == ".rb"
        end
    end

    def entrypoint
        codes.each do |key, val|
            if val["content"].include? "Plugin.create"
                return {name: key, values: val, slug: File.basename(key, ".rb").to_sym}
            end
        end
        {}
    end

    def spec
        {
            slug: entrypoint[:slug],
            depends: {
                mikutter: Environment::VERSION.to_s,
                plugin: []
            },
            version: "1.0",
            author: @gist["owner"]["login"],
            name: entrypoint[:name],
            description: "",
            repository: @gist["git_pull_url"]
        }
    end

    attr_reader :id
end

Plugin.create :mikutter_gist_installer do
    @@gists = {}

    def show_gist(id, force = false)
        slug = "gist-#{id}".to_sym
        if !force and Plugin::GUI::Tab.exist?(slug)
            Plugin::GUI::Tab.instance(slug).active!
        else
            SerialThread.new do
                UserConfig[:opened_gists] = ((UserConfig[:opened_gists] || []) + [id]).uniq
                
                uri = URI.parse("https://api.github.com/gists/#{id}")
                json = JSON.parse(Net::HTTP.get(uri))
                @@gists[id] = json

                gist = Gist.new(id, json)
                entrypoint = gist.entrypoint
                p entrypoint
                
                Delayer.new do
                    gist_tab = tab(slug, "Gist/#{id}") do
                        set_deletable true
                        shrink
                        hbox = Gtk::HBox.new
                        hbox.pack_start Gtk::Label.new("#{json["owner"]["login"]}/#{entrypoint[:name]}", false), true, true
                        install_button = Gtk::Button.new
                        if Plugin::Mikustore::Utils.installed_version(entrypoint[:slug])
                            install_button.set_label("アンインストール")
                        else
                            install_button.set_label("インストール")
                        end
                        install_button.signal_connect("clicked") do
                            if Plugin::Mikustore::Utils.installed_version(entrypoint[:slug])
                                # Uninstall
                                spec = gist.spec
                                Plugin.uninstall(spec[:slug])
                                plugin_dir = File.expand_path(File.join(Environment::USER_PLUGIN_PATH, spec[:slug].to_s))
                                if FileTest.exist?(plugin_dir)
                                    FileUtils.rm_rf(plugin_dir)
                                end
                                install_button.set_label("インストール")
                            else
                                # Install
                                installer = Plugin::Mikustore::Installer.new(gist.spec)
                                if installer.valid
                                    install_button.sensitive = false
                                    install_button.set_label("インストール中")
                                    installer.install.next do
                                        install_button.sensitive = true
                                        install_button.set_label("アンインストール")
                                    end.trap do |e|
                                        Gtk::Dialog.alert("プラグインのインストールに失敗しました。")
                                        install_button.sensitive = true
                                        install_button.set_label("インストール")
                                        notice e
                                        raise e
                                    end.terminate("プラグインのインストールに失敗しました。")
                                else
                                    Gtk::Dialog.alert("依存関係の解析に失敗しました。")
                                end
                            end
                        end
                        hbox.pack_end install_button, false, false
                        browser_button = Gtk::Button.new("ブラウザで開く")
                        browser_button.signal_connect("clicked") do
                            ::Gtk.openurl("https://gist.github.com/#{id}")
                        end
                        hbox.pack_end browser_button, false, false
                        nativewidget hbox
                        expand
                        frame = Gtk::Frame.new("Code")
                        vbox = Gtk::VBox.new
                        vbox.pack_start Gtk::Label.new("※ 信用できるプラグイン以外はインストールしないでください ※"), false, false
                        swindow = Gtk::ScrolledWindow.new
                        swindow.set_shadow_type Gtk::SHADOW_NONE

                        textview = Gtk::TextView.new
                        textview.buffer.set_text entrypoint[:values]["content"]
                        textview.set_editable false
                        textview.set_wrap_mode Gtk::TextTag::WRAP_CHAR

                        swindow.add_with_viewport(textview)
                        vbox.pack_start swindow, true, true
                        frame << vbox
                        nativewidget frame
                    end
                    gist_tab.active! if !force
                end
            end
        end
    end

    Gtk::TimeLine.addopenway(/^https?:\/\/gist\.github\.com\/.+\/[a-f0-9]+/) do |shrinked_url, cancel|
        url = MessageConverters.expand_url_one(shrinked_url)
        if /^https?:\/\/gist\.github\.com\/.+\/([a-f0-9]+)/ =~ url
            show_gist($1)
        end
    end

    on_gui_destroy do |widget|
        if widget.is_a? Plugin::GUI::Tab
            /gist-([a-f0-9]+)/ =~ widget.slug
            UserConfig[:opened_gists] = UserConfig[:opened_gists].melt.reject {|id| id==$1}
        end
    end

    Delayer.new do
        (UserConfig[:opened_gists] || []).uniq.each do |id|
            show_gist(id, true)
        end
    end
end
