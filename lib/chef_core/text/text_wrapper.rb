#
# Copyright:: Copyright (c) 2017 Chef Software Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

module ChefCore
  module Text
    # TextWrapper is a wrapper around R18n that returns all resolved values
    # as Strings, and raise an error when a given i18n key is not found.
    #
    # This simplifies behaviors when interfacing with other libraries/components
    # that don't play nicely with TranslatedString or Untranslated out of R18n.
    class TextWrapper
      def initialize(translation_tree)
        @tree = translation_tree
        @tree.translation_keys.each do |k|
          # Integer keys are not translatable - they're quantity indicators in the key that
          # are instead sent as arguments. If we see one here, it means it was not correctly
          # labeled as plural with !!pl in the parent key
          if k.class == Integer
            raise MissingPlural.new(@tree.instance_variable_get(:@path), k)
          end

          k = k.to_sym
          define_singleton_method k do |*args|
            subtree = @tree.send(k, *args)
            if subtree.methods.include?(:translation_keys) && !subtree.translation_keys.empty?
              # If there are no more possible children, just return the translated value
              TextWrapper.new(subtree)
            else
              subtree.to_s
            end
          end
        end
      end

      def method_missing(name, *args)
        raise InvalidKey.new(@tree.instance_variable_get(:@path), name)
      end

      # TODO - make the checks for these conditions lint steps that run during build
      #        instead of part of the shipped product.
      class TextError < RuntimeError
        attr_accessor :line
        def set_call_context
          # TODO - this can vary (8 isn't always right) - inspect
          @line = caller(8, 1).first
          if @line =~ %r{.*/lib/(.*\.rb):(\d+)}
            @line = "File: #{$1} Line: #{$2}"
          end
        end
      end

      class InvalidKey < TextError
        def initialize(path, terminus)
          set_call_context
          # Calling back into Text here seems icky, this is an error
          # that only engineering should see.
          message = "i18n key #{path}.#{terminus} does not exist.\n"
          message << "  Referenced from #{line}"
          super(message)
        end
      end

      class MissingPlural < TextError
        def initialize(path, terminus)
          set_call_context
          message = "i18n key #{path}.#{terminus} appears to reference a pluralization.\n"
          message << "  Please append the plural indicator '!!pl' to the end of #{path}.\n"
          message << "  Referenced from #{line}"
          super(message)
        end
      end
    end
  end
end
