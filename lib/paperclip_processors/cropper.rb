require "paperclip"

module Paperclip
  class Cropper < Thumbnail

    def initialize(file, options = {}, attachment = nil)
      @style = options[:style]
      super
    end

    # def make
    #   if crop_command
    #     super
    #   else
    #     src = @file
    #     filename = [@basename, @format ? ".#{@format}" : ""].join

    #     dst = TempfileFactory.new.generate(filename)

    #     # Leaves blank files
    #     dst
    #   end
    # end

    def transformation_command
      if crop_command
        crop_command + super.join(' ').sub(/ -crop \S+/, '').split(' ')
      else
        super
      end
    end


    def crop_command
      target = @attachment.instance

      if target.cropping?(@attachment.name, @style)
        w = target.get_crop_attribute(@attachment.name, @style, 'crop_w') # :"#{@attachment.name}_crop_w"
        h = target.get_crop_attribute(@attachment.name, @style, 'crop_h') # :"#{@attachment.name}_crop_h"
        x = target.get_crop_attribute(@attachment.name, @style, 'crop_x') # :"#{@attachment.name}_crop_x"
        y = target.get_crop_attribute(@attachment.name, @style, 'crop_y') # :"#{@attachment.name}_crop_y"
        ["-crop", "#{w}x#{h}+#{x}+#{y}"]
      end
    end

  end
end
