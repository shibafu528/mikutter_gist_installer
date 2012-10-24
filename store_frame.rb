# -*- coding: utf-8 -*-
require File.expand_path(File.join(File.dirname(__FILE__), "plugins_list"))
require File.expand_path(File.join(File.dirname(__FILE__), "plugin_detail"))

module Plugin::Mikustore
  class StoreFrame < Gtk::HPaned

    attr_reader :packages, :detail

    def initialize
      super
      @packages = Plugin::Mikustore::PluginsList.new.set_width_request(180)
      @detail = Plugin::Mikustore::PluginDetail.new
      @packages.signal_connect("row-activated"){|view, path, column|
        iter = view.model.get_iter(path)
        @detail.set_package(iter[2])
      }
      ssc(:parent_set){
        Delayer.new {
          if not destroyed?
            window = get_ancestor(Gtk::Window)
            if window and not window.destroyed?
              get_ancestor(Gtk::Window).ssc(:event, self) { |window, event|
                set_height_request(window.window.geometry[3])
                false } end end } }
      pack1 @packages, false, false
      pack2 @detail, true, false
    end

  end
end