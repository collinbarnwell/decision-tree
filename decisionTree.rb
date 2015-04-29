
require 'csv'
# require 'pry'

# TODO: deal w/ nil attribute testing

SPLIT_MAX = 4
MAX_ITERATIONS = 1000

def median(ary)
  # from http://stackoverflow.com/questions/21487250/find-the-median-of-an-array
  mid = ary.length / 2
  sorted = ary.sort
  ary.length.odd? ? sorted[mid] : 0.5 * (sorted[mid] + sorted[mid - 1])
end

class TreeBuilder
  def self.recursiveBuild(datas, atts_left, numSplits)
    # nominals = {att => [c1, c2, c3], att => nil, att => [c1, c2], att => nil}

    puts atts_left.inspect

    if atts_left.empty?
      # return Leaf if no splits left
      outcount = Hash.new(0)

      datas.map(&:output).each do |d|
        outcount[d]+=1
      end

      return Leaf.new(outcount.max_by{|k,v| v}.first)
    end

    if datas.map(&:output).all?{|obj| obj == datas.first.output }
      # return Leaf if all_the_same
      return Leaf.new(datas.first.output)
    end

    best_entr = 0
    best_thresh = nil
    best_att = nil
    examples = datas.count

    atts_left.each do |a|
      if @@nom_choices[a]
        # attribute is nominal
        outcomes_count = Hash.new(0)
        datas.each do |d|
          outcomes_count[d.vals[a]]+=1
        end

        entropy = 0
        outcomes_count.each do |k, v|
          entropy += -(v/examples)*Math.log2(v/examples)
        end

      else
        # attribute is continuous
        # puts datas.select.map{ |d| d.vals[a] }.inspect
        puts a
        # puts @@nom_choices.inspect
        median = median( datas.select.map{ |d| d.vals[a] } )
        entropy = -Math.log2(0.5)
      end

      if entropy >= best_entr
        best_entr = entropy
        best_att = a
        best_thresh = median if median
      end
    end

    if @@nom_choices[best_att]
      atts_left = atts_left - [best_att]
      n = Node.new(best_att)
    else
      atts_left = atts_left - [best_att] if (numSplits[best_att]+=1) >= SPLIT_MAX
      n = Node.new(best_att, best_thresh)
    end

    # split datas and recurse to add children
    # kids array goes lowest to igest, left to rigt in nomCoices
    kids = []
    if @@nom_choices[best_att]
      @@nom_choices[best_att].each do |possible_val|
        datac = datas.select { |d| d.vals[best_att] == possible_val }
        kids << recursiveBuild(datac, atts_left, numSplits)
      end
    else
      datac1 = datas.select { |d| d.vals[best_att] < best_thresh }
      datac2 = datas.select { |d| d.vals[best_att] >= best_thresh }
      kids = [recursiveBuild(datac1, atts_left, numSplits),
              recursiveBuild(datac2, atts_left, numSplits)]
    end

    n.addChildren(kids)

    return n
  end

  def self.buildTree(csvin)
    datas = []
    keys = []
    @@nom_choices = Hash.new(nil)

    iteration = 0
    CSV.foreach(csvin) do |row|
      iteration+=1
      if iteration == 1
        # take keys
        keys = row.map{ |k| k.gsub(' ','') }

        next
      elsif iteration == 2
        # set nominal stuff
        puts row.inspect
        keys.each_with_index do |k, ind|
          if row[ind].nil?
            @@nom_choices[k] = nil
            print '#,'
          else
            @@nom_choices[k] = []
            print 'nom,'
          end
        end

        puts
        next
      end

      keys[0...-1].each_with_index do |a, i|
        if @@nom_choices[a].nil?
          if row[i] == '?'
            row[i] = 0.0 
          else
            # change data into a number if it isn't nominal
            row[i] = row[i].to_f
          end
        else
          # otherwise check to see if its represented in @@nom_choices
          @@nom_choices[a]+=[row[i]] unless @@nom_choices[a].include?(row[i])
        end
      end

      datas << Datum.new(keys, row)
      break if iteration >= MAX_ITERATIONS
    end

    puts "Finished reading data."

    tree = recursiveBuild(datas, keys[0...-1], Hash.new(0))
    tree.print(0)
  end
end

class Datum < TreeBuilder
  # contains one data instance from training set
  attr_accessor :vals
  attr_reader :output

  def initialize(attrs, vals)
    @vals = Hash.new(nil)
    # if vals.last == '?'
    #   @output = -1
    # else
    @output = vals.last.to_i
    # end
    attrs[0...-1].each_with_index do |a, ind|
      @vals[a] = vals[ind]
    end
  end
end

class Node < TreeBuilder
  # Either assigns classification or passes or tests for other nodes
  # Sends to one child after testing value

  def initialize(att, thresh=nil)
    if thresh
      @nominal = false
      @thresh = thresh
    else
      @nominal = true
    end
    @att = att
  end

  def addChildren(kids)
    @children = kids
  end

  # kids array goes lowest to igest, left to rigt in nomCoices
  def test(data)
    if @nominal
      @children.each_with_index do |child, ind|
        # TODO: this doesn't work:
        child.test(data, @@nom_choices) if data[@att] == @@nom_choices[@att][ind]
      end
    else
      if data[@att] < @thresh # > on one side, <= on oter
        @children.first.test(data)
      else
        @children[1].test(data, nom_choices)
      end
    end
  end

  def print(dots)
    str = "."*dots + "ON #{@att}: "
    if @nominal
      str += "("
      @@nom_choices[@att].each do |c|
        str+=c
        str+= "|"
      end
      puts str + ")"
    else
      puts str + ",thresh: #{@thresh}"
    end

    @children.each do |c|
      c.print(dots+1, @@nom_choices)
    end
  end
end

class Leaf < Node
  # overloads test function to assign value after testing value
  def initialize(klassification)
    @klass = klassification
  end

  def test(data, nom_choices)
    @klass
  end

  def print(dots)
    puts "."*dots + "!OUT: #{@klass}"
  end
end

