# -*- coding: utf-8 -*-
require File.expand_path(File.join(File.dirname(__FILE__), "utils"))

module Plugin::Mikustore
  class Installer
    attr_reader :valid

    def initialize(package, *opt)
      kwargs = opt.first || {}
      @plugin = package
      @depends = []
      @plugin_base = kwargs[:plugin_base] || "~/.mikutter/plugin"
      @database = {}
      Plugin.filtering(:mikustore_plugins, []).first.each do |entry|
        @database[entry[:slug]] = entry
      end
      begin
        @depends = analyze_dependency(@plugin)
        @valid = true
        #puts @depends.inspect
      rescue => e
        notice e
        @valid = false
      end
    end

    def install
      specs = @depends.map{|slug| @database[slug]}
      specs.reduce(Thread.new{}){|prev,dep| prev.next{install_it(dep)}}.trap {|e|
        if e.is_a? Hash # plugin spec
          revert_it(e)
        end
        Deffered.fail
      }
    end

    private

    def analyze_dependency(plugin)
      # 依存してるプラグインを幅優先探索で列挙していく．
      level = 0
      q = [plugin]
      found = {plugin[:slug].to_sym => level}
      while not q.empty?
        level += 1
        next_q = []
        q.each do |current|
          if current[:depends] && current[:depends][:plugin]
            current[:depends][:plugin].each do |depend|
              depend_sym = depend.to_sym
              depend_level = found[depend_sym]
              # 以前に訪問したノードを再訪問しようとしていれば，循環参照が発生している．
              if depend_level && depend_level < level
                raise "Circular dependency detected."
              end
              if depend_level.nil? && Plugin::Mikustore::Utils.installed_version(depend_sym).nil? 
                depend_spec = @database[depend_sym]
                if depend_spec
                  next_q << depend_spec
                  found[depend_sym] = level
                else
                  # 依存してるプラグインのインストール方法が分からない時はとりあえず例外投げとく．
                  raise "Missing dependency: #{depend}"
                end
              end
            end
          end
        end
        q = next_q
      end
      found.to_a.sort_by{|e| e[1]}.map{|e| e[0]}.reverse
    end

    def install_it(plugin)
      main_file = install_git(plugin)
      load_it(main_file, plugin)
    end

    def load_it(file, plugin)
      notice "plugin load: #{file}"
      Plugin.load_file(file, plugin)
    end

    def revert_it(plugin)
      revert_git(plugin)
    end

    def install_git(package)
      plugin_dir = File.expand_path(File.join("#{@plugin_base}", package[:slug].to_s))
      Deferred.fail(Exception.new("#{plugin_dir} already exists.")) if FileTest.exist?(plugin_dir)

      if system("git clone #{package[:repository]} #{plugin_dir}")
        File.join(plugin_dir, "#{package[:slug]}.rb")
      else
        Deferred.fail(package)
      end
    end

    def revert_git(package)
      plugin_dir = File.expand_path(File.join("#{@plugin_base}", package[:slug].to_s))
      if FileTest.exist?(plugin_dir)
        FileUtils.rm_rf(plugin_dir)
      end
    end
  end
end