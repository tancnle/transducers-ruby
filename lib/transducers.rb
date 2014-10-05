# Copyright 2014 Cognitect. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS-IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Transducers enable composable algorithmic transformations by transforming
# reducers.
#
# A reducer is an object with a +step+ operation that takes a result
# (so far) and an input and returns a new result. This is similar to
# the blocks we pass to Ruby's +reduce+ (a.k.a +inject+), and serves a
# similar role in transducing operation.
#
# Each transducer will wrap a reducer in its own reducer, thereby
# transforming the behavior of the wrapped reducer
#
# For example, let's say you want to take a range of numbers, select
# all the even numbers, double them, and then take the first 5. Here's
# one way to do that in Ruby:
#
# ```ruby
# (1..100).
#   select {|n| n.even?}.
#   map    {|n| n * 2}.
#   take(5)
# #=> [4, 8, 12, 16, 20]
# ```
#
# Here's the same process with transducers:
#
# ```ruby
# t = Transducers.compose(
#       Transducers.filter(:even?),
#       Transducers.map {|n| n * 2},
#       Transducers.take(5))
# Transducers.transduce(t, :<<, [], 1..100)
# #=> [4, 8, 12, 16, 20]
# ```
#
# The transduce method builds a reducer sending +:<<+ to an initial
# value of +[]+.  Now that we've defined the transducer as a series of
# transformations, we can apply it to different contexts, e.g.
#
# ```ruby
# Transducers.transduce(t, :+, 0, 1..100)
# #=> 60
# Transducers.transduce(t, :*, 1, 1..100)
# #=> 122880
# ```
module Transducers
  class Reducer
    def initialize(init, sym=nil, &block)
      raise ArgumentError.new("No init provided") if init == :no_init_provided
      @init = init
      if sym
        @sym = sym
        (class << self; self; end).class_eval do
          def step(result, input)
            result.send(@sym, input)
          end
        end
      else
        @block = block
        (class << self; self; end).class_eval do
          def step(result, input)
            @block.call(result, input)
          end
        end
      end
    end

    def init()           @init  end
    def complete(result) result end
    def step(result, input)
      # placeholder for docs - overwritten in initalize
    end
  end

  class Reduced
    attr_reader :val

    def initialize(val)
      @val = val
    end
  end

  class PreservingReduced
    def apply(reducer)
      @reducer = reducer
    end

    def step(result, input)
      ret = @reducer.step(result, input)
      Reduced === ret ? Reduced.new(ret) : ret
    end
  end

  class WrappingReducer
    class BlockHandler
      def initialize(block)
        @block = block
        # Define the process method based on the block's arity.  It's
        # more efficient to do this once when this handler is
        # initialized than to handle varargs (possibly multiple times)
        # for each input in a transduce process.
        (class << self; self; end).class_eval do
          case block.arity
          when 1
            def process(input)
              @block.call(input)
            end
          when 2
            def process(a,b)
              @block.call(a,b)
            end
          else
            def process(a, b, *etc)
              @block.call(a, b, *etc)
            end
          end
        end
      end
    end

    class MethodHandler
      def initialize(method)
        @method = method
      end

      def process(input)
        input.send @method
      end
    end

    def initialize(reducer, handler=nil, &block)
      @reducer = reducer
      @handler = if block
                   BlockHandler.new(block)
                 elsif Symbol === handler
                   MethodHandler.new(handler)
                 else
                   handler
                 end
    end

    def init()
      @reducer.init
    end

    def complete(result)
      @reducer.complete(result)
    end
  end

  # @api private
  class BaseTransducer
    class << self
      attr_reader :reducer_class

      def define_reducer_class(&block)
        @reducer_class = Class.new(WrappingReducer)
        @reducer_class.class_eval(&block)
      end
    end

    def initialize(handler, &block)
      @handler = handler
      @block = block
    end

    def reducer_class
      self.class.reducer_class
    end
  end

  class << self
    # @overload transduce(transducer, reducer, coll)
    # @overload transduce(transducer, reducer, init, coll)
    # @param [Transducer] transducer
    # @param [Reducer, Symbol, Bock] reducer
    def transduce(transducer, reducer, init=:no_init_provided, coll)
      reducer = Reducer.new(init, reducer) unless reducer.respond_to?(:step)
      reducer = transducer.apply(reducer)
      result = init == :no_init_provided ? reducer.init : init
      m = case coll
          when Enumerable then :each
          when String     then :each_char
          end
      coll.send(m) do |input|
        return result.val if Transducers::Reduced === result
        result = reducer.step(result, input)
      end
      result
    end

    def self.define_transducer_class(name, &block)
      t = Class.new(BaseTransducer)
      t.class_eval(&block)
      unless t.instance_methods.include? :apply
        t.class_eval do
          define_method :apply do |reducer|
            reducer_class.new(reducer, @handler, &@block)
          end
        end
      end

      Transducers.send(:define_method, name) do |handler=nil, &b|
        t.new(handler, &b)
      end

      Transducers.send(:module_function, name)
    end

    # @macro [new] common_transducer
    #   @return [Transducer]
    #   @method $1(handler=nil, &block)
    #   @param [Object, Symbol] handler
    #     Given an object that responds to +process+, uses it as the
    #     handler.  Given a +Symbol+, builds a handler whose +process+
    #     method will send +Symbol+ to its argument.
    #   @param [Block] block <i>(optional)</i>
    #     Given a +Block+, builds a handler whose +process+ method will
    #     call the block with its argument(s).
    define_transducer_class :map do
      define_reducer_class do
        # Can I doc this?
        def step(result, input)
          @reducer.step(result, @handler.process(input))
        end
      end
    end

    # @macro common_transducer
    define_transducer_class :filter do
      define_reducer_class do
        def step(result, input)
          @handler.process(input) ? @reducer.step(result, input) : result
        end
      end
    end

    # @macro common_transducer
    define_transducer_class :remove do
      define_reducer_class do
        def step(result, input)
          @handler.process(input) ? result : @reducer.step(result, input)
        end
      end
    end

    # @method take(n)
    # @return [Transducer]
    define_transducer_class :take do
      define_reducer_class do
        def initialize(reducer, n)
          super(reducer)
          @n = n
        end

        def step(result, input)
          @n -= 1
          if @n == -1
            Reduced.new(result)
          else
            @reducer.step(result, input)
          end
        end
      end

      def initialize(n)
        @n = n
      end

      def apply(reducer)
        reducer_class.new(reducer, @n)
      end
    end

    # @macro common_transducer
    define_transducer_class :take_while do
      define_reducer_class do
        def step(result, input)
          @handler.process(input) ? @reducer.step(result, input) : Reduced.new(result)
        end
      end
    end

    # @method take_nth(n)
    # @return [Transducer]
    define_transducer_class :take_nth do
      define_reducer_class do
        def initialize(reducer, n)
          super(reducer)
          @n = n
          @count = 0
        end

        def step(result, input)
          @count += 1
          if @count % @n == 0
            @reducer.step(result, input)
          else
            result
          end
        end
      end

      def initialize(n)
        @n = n
      end

      def apply(reducer)
        reducer_class.new(reducer, @n)
      end
    end

    # @method replace(source_map)
    # @return [Transducer]
    define_transducer_class :replace do
      define_reducer_class do
        def initialize(reducer, smap)
          super(reducer)
          @smap = smap
        end

        def step(result, input)
          if @smap.has_key?(input)
            @reducer.step(result, @smap[input])
          else
            @reducer.step(result, input)
          end
        end
      end

      def initialize(smap)
        @smap = case smap
                when Hash
                  smap
                else
                  smap.reduce({}) {|h,v| h[h.count] = v; h}
                end
      end

      def apply(reducer)
        reducer_class.new(reducer, @smap)
      end
    end

    # @macro common_transducer
    define_transducer_class :keep do
      define_reducer_class do
        def step(result, input)
          x = @handler.process(input)
          if x.nil?
            result
          else
            @reducer.step(result, x)
          end
        end
      end
    end

    # @macro common_transducer
    # @note the handler for this method requires two arguments: the
    #   index and the input.
    define_transducer_class :keep_indexed do
      define_reducer_class do
        def initialize(*)
          super
          @index = -1
        end

        def step(result, input)
          @index += 1
          x = @handler.process(@index, input)
          if x.nil?
            result
          else
            @reducer.step(result, x)
          end
        end
      end
    end

    # @method drop(n)
    # @return [Transducer]
    define_transducer_class :drop do
      define_reducer_class do
        def initialize(reducer, n)
          super(reducer)
          @n = n
        end

        def step(result, input)
          @n -= 1

          if @n <= -1
            @reducer.step(result, input)
          else
            result
          end
        end
      end

      def initialize(n)
        @n = n
      end

      def apply(reducer)
        reducer_class.new(reducer, @n)
      end
    end

    # @macro common_transducer
    define_transducer_class :drop_while do
      define_reducer_class do
        def initalize(*)
          super
          @done_dropping = false
        end

        def step(result, input)
          @done_dropping ||= !@handler.process(input)
          @done_dropping ? @reducer.step(result, input) : result
        end
      end
    end

    # @method dedupe
    # @return [Transducer]
    define_transducer_class :dedupe do
      define_reducer_class do
        def initialize(*)
          super
          @n = -1
          @prior = nil
        end

        def step(result, input)
          @n += 1
          ret = if @n > 0 && input == @prior
                  result
                else
                  @reducer.step(result, input)
                end
          @prior = input
          ret
        end
      end
    end

    # @method cat
    # @return [Transducer]
    define_transducer_class :cat do
      define_reducer_class do
        def step(result, input)
          Transducers.transduce(PreservingReduced.new, @reducer, result, input)
        end
      end
    end

    # @api private
    class ComposedTransducer
      def initialize(*transducers)
        @transducers = transducers
      end

      def apply(reducer)
        @transducers.reverse.reduce(reducer) {|r,t| t.apply(r)}
      end
    end

    # @return [Transducer]
    def compose(*transducers)
      ComposedTransducer.new(*transducers)
    end

    # @return [Transducer]
    def mapcat(handler=nil, &block)
      compose(map(handler, &block), cat)
    end
  end
end
