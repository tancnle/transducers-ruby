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

require 'spec_helper'

RSpec.describe Transducers do
  include Transducers

  alias orig_expect expect

  def expect(expected, &actual)
    orig_expect(actual.call).to eq(expected)
  end

  it "creates a mapping transducer with a block" do
    expect([2,3,4]) do
      transduce(mapping {|n| n + 1}, :<<, [], [1,2,3])
    end
  end

  it "creates a mapping transducer with a Symbol" do
    expect([2,3,4]) do
      transduce(mapping(:succ), :<<, [], [1,2,3])
    end
  end

  it "creates a mapping transducer with an object that implements process" do
    inc = Class.new do
      def process(n) n + 1 end
    end.new

    expect([2,3,4]) do
      transduce(mapping(inc), :<<, [], [1,2,3])
    end
  end

  it "creates a filtering transducer with a Symbol" do
    expect([2,4]) do
      transduce(filtering(:even?), :<<, [], [1,2,3,4,5])
    end
  end

  it "creates a filtering transducer with a Block" do
    expect([2,4]) do
      transduce(filtering {|x| x.even?}, :<<, [], [1,2,3,4,5])
    end
  end

  it "creates a filtering transducer with an object that implements process" do
    expect([2,4]) do
      even = Class.new do
        def process(n) n.even? end
      end.new
      transduce(filtering(even), :<<, [], [1,2,3,4,5])
    end
  end



  it "creates a removing transducer with a Symbol" do
    expect([1,3,5]) do
      transduce(removing(:even?), :<<, [], [1,2,3,4,5])
    end
  end

  it "creates a removing transducer with a Block" do
    expect([1,3,5]) do
      transduce(removing {|x| x.even?}, :<<, [], [1,2,3,4,5])
    end
  end

  it "creates a removing transducer with an object that implements process" do
    expect([1,3,5]) do
      even = Class.new do
        def process(n) n.even? end
      end.new
      transduce(removing(even), :<<, [], [1,2,3,4,5])
    end
  end









  it "creates a taking transducer" do
    expect([1,2,3,4,5]) do
      transduce(taking(5), :<<, [], 1.upto(20))
    end
  end

  it "creates a dropping transducer" do
    expect([16,17,18,19,20]) do
      transduce(dropping(15), :<<, [], 1.upto(20))
    end
  end

  it "creates a cat transducer" do
    expect([1,2,3,4]) do
      transduce(cat, :<<, [], [[1,2],[3,4]])
    end
  end

  it "creates a mapcat transducer with an object" do
    range_builder = Class.new do
      def process(n) 0...n; end
    end.new

    expect([0,0,1,0,1,2]) do
      transduce(mapcat(range_builder), :<<, [], [1,2,3])
    end
  end

  it "creates a mapcat transducer with a block" do
    expect([0,0,1,0,1,2]) do
      transduce(mapcat {|n| 0...n}, :<<, [], [1,2,3])
    end
  end

  it "transduces a String" do
    expect("THIS") do
      transduce(mapping {|c| c.upcase},
                Transducers::Reducer.new("") {|r,i| r << i},
                "this")
    end
  end

  it "transduces a range" do
    expect([2,3,4]) do
      transduce(mapping(:succ), :<<, [], 1..3)
    end
  end

  it "raises when no initial value method is defined on the reducer" do
    orig_expect do
      r = Class.new { def step(_,_) end }.new
      transduce(mapping(:succ), r, [1,2,3])
    end.to raise_error(NoMethodError)
  end

  it "raises when it receives a symbol but no initial value" do
    orig_expect do
      transduce(mapping(:succ), :<<, [1,2,3])
    end.to raise_error(ArgumentError, "No init provided")
  end

  describe "composition" do
    example do
      expect([3,7]) do
        td = compose(mapping {|a| [a.reduce(&:+)]}, cat)
        transduce(td, :<<, [], [[1,2],[3,4]])
      end
    end

    example do
      expect(12) do
        td = compose(taking(5),
                   mapping {|n| n + 1},
                   filtering(:even?))
        transduce(td, :+, 0, 1..20)
      end
    end
  end
end
