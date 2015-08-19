module Papercrop
  module ModelExtension

    module ClassMethods

      # Initializes attachment cropping in your model
      #
      #   crop_attached_file :avatar
      #
      # You can also define an aspect ratio for the crop and preview box through opts[:aspect]
      #
      #   crop_attached_file :avatar, :aspect => "4:3"
      #
      # @param attachment_name [Symbol] Name of the desired attachment to crop
      # @param opts [Hash]
      def crop_attached_file(attachment_name, opts = {})
        if respond_to? :attachment_definitions
          # for Paperclip <= 3.4
          definitions = attachment_definitions
        else
          # for Paperclip >= 3.5
          definitions = Paperclip::Tasks::Attachments.instance.definitions_for(self)
        end

        definitions[attachment_name][:processors] ||= []
        # definitions[attachment_name][:processors] = definitions[attachment_name][:processors] - [:thumbnail]
        definitions[attachment_name][:processors] << :cropper

        after_update :"reprocess_to_crop_#{attachment_name}_attachment"
      end

      def crop_attribute_suffixes
        %i(crop_x crop_y crop_w crop_h original_w original_h box_w cropped_geometries aspect)
      end

      def crop_attribute_names(attachment_name, style)
        crop_attribute_suffixes.map { |suffix| crop_attribute_name(attachment_name, style, suffix) }
      end

      def crop_attribute_name(attachment_name, style, suffix)
        :"#{attachment_name}__#{style}_#{suffix}"
      end

      def get_crop_attribute_method_regex
        /_#{crop_attribute_suffixes.map(&:to_s).join('$|_')}$/
      end

      def set_crop_attribute_method_regex
        /_#{crop_attribute_suffixes.map(&:to_s).join('=$|_')}=$/
      end
    end

    module InstanceMethods

      # Asks if the attachment received a crop process
      # @param  attachment_name [Symbol]
      #
      # @return [Boolean]
      def cropping?(attachment_name, style)
        !self.get_crop_attribute(attachment_name, style, 'crop_x').blank? &&
        !self.get_crop_attribute(attachment_name, style, 'crop_y').blank? &&
        !self.get_crop_attribute(attachment_name, style, 'crop_w').blank? &&
        !self.get_crop_attribute(attachment_name, style, 'crop_h').blank?
      end

      # Returns a Paperclip::Geometry object of a given attachment
      #
      # @param attachment_name [Symbol]
      # @param style = :original [Symbol] attachment style
      # @return [Paperclip::Geometry]
      def image_geometry(attachment_name, style = :original)
        @geometry ||= {}
        path = (self.send(attachment_name).options[:storage] == :s3) ? self.send(attachment_name).url(style) : self.send(attachment_name).path(style)
        @geometry[style] ||= Paperclip::Geometry.from_file(path)
      end

      def styles(attachment_name)
        self.send(attachment_name).styles.map { |key, value| [key, value.geometry] }.to_h
      end

      def dimensions_for_style(attachment_name, style)
        styles(attachment_name)[style].match(/(\d+)x(\d+)/).to_a.drop(1).map(&:to_f)
      end

      # Uses method missing to responding the model callback
      def method_missing(method, *args)
        if method.to_s =~ Papercrop::RegExp::CALLBACK
          reprocess_cropped_attachment(
            method.to_s.scan(Papercrop::RegExp::CALLBACK).flatten.first.to_sym
          )
        elsif method.to_s =~ self.class.get_crop_attribute_method_regex
          get_crop_attribute(*method.to_s.gsub(self.class.get_crop_attribute_method_regex, '').split('__'), $~.to_s.gsub(/^\_/, '')) # $~ is last match
        elsif method.to_s =~ self.class.set_crop_attribute_method_regex
          set_crop_attribute(*method.to_s.gsub(self.class.set_crop_attribute_method_regex, '').split('__'), $~.to_s.gsub(/^\_/, '').gsub('=', ''), args.first) # $~ is last match
        else
          super
        end
      end

      def set_crop_attribute(attachment_name, style, attribute, value)
        write_attribute(:updated_at, Time.now) unless value == get_crop_attribute(attachment_name, style, attribute)
        instance_variable_set("@#{[attachment_name, style, attribute].join('_')}", value)
      end

      def get_crop_attribute(attachment_name, style, attribute)
        instance_variable_get("@#{[attachment_name, style, attribute].join('_')}")
      end

      # Sets all cropping attributes to nil
      # @param  attachment_name [Symbol]
      def reset_crop_attributes_of(attachment_name)
        styles(attachment_name).keys.each do |style|
          [:crop_x, :crop_y, :crop_w, :crop_h].each do |a|
            self.send :"#{attachment_name}__#{style}_#{a}=", nil
          end
        end
      end

      private

        # Saves the attachment if the crop attributes are present
        # @param  attachment_name [Symbol]
        def reprocess_cropped_attachment(attachment_name)
          if styles(attachment_name).keys.map { |style| cropping?(attachment_name, style) }.include?(true)
            attachment_instance = send(attachment_name)
            attachment_instance.assign(attachment_instance)
            attachment_instance.save

            reset_crop_attributes_of(attachment_name)
          end
        end

    end
  end
end


# ActiveRecord support
if defined? ActiveRecord::Base
  ActiveRecord::Base.class_eval do
    extend  Papercrop::ModelExtension::ClassMethods
    include Papercrop::ModelExtension::InstanceMethods
  end
end


# Mongoid support
if defined? Mongoid::Document
  Mongoid::Document::ClassMethods.module_eval do
    include Papercrop::ModelExtension::ClassMethods
  end

  Mongoid::Document.module_eval do
    include Papercrop::ModelExtension::InstanceMethods
  end
end
