require 'csv'

SPLIT_MAX = 1
MAX_ITERATIONS = 10000
RESTRICT_PRINT_TO_16 = false

def median(ary)
  # from http://stackoverflow.com/questions/21487250/find-the-median-of-an-array
  mid = ary.length / 2
  sorted = ary.sort
  ary.length.odd? ? sorted[mid] : 0.5 * (sorted[mid] + sorted[mid - 1])
end

class Array; def in_groups(num_groups)
  # from http://stackoverflow.com/questions/12374645
  # /splitting-an-array-into-equal-parts-in-ruby
  return [] if num_groups == 0
  slice_size = (self.size/Float(num_groups)).ceil
  self.each_slice(slice_size).to_a
end; end

class TreeBuilder
  def self.recursiveBuild(datas, atts_left, numSplits)
    # nominals = {att => [c1, c2, c3], att => nil, att => [c1, c2], att => nil}

    if datas.empty?
      return Leaf.new(@@output_choices.first)
    end

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
        median = median( datas.select.map{ |d| d.vals[a] } )
        entropy = -Math.log2(0.5)
      end

      if entropy >= best_entr
        best_entr = entropy
        best_att = a
        best_thresh = median if median
      end
    end

    if best_att.nil?
      return Leaf.new(datas.first.output)
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

  def self.learningCurve(csvin, validate)
    num_examples = 50000
    num_trains = 0

    while num_trains < num_examples - 5000
      num_trains += 5000
      num_tests = num_examples - num_trains

      validation_data = []

      count = 0
      datas = []
      iteration = 0
      CSV.foreach(validate) do |row|
        iteration+=1

        next if iteration == 1 or iteration == 2

        if iteration >= num_tests
          validation_data << Datum.new(row)
        else
          datas << Datum.new(row)
        end
      end

      tree = buildTree(csvin, num_trains)
      tree.prune(@@datas, validation_data)

      correct = 0
      wrong = 0
      datas.each do |d|
        actual = tree.test(d)
        if d.output == actual
          correct+=1
        else
          wrong+=1
        end
      end

      puts "Num Trains: #{num_trains} - #{100*correct.to_f/(correct+wrong).to_f}%"
    end
  end

  def self.testOn(tree, datas, label, print = false)
    correct = 0
    wrong = 0
    datas.each do |d|
      actual = tree.test(d)
      if d.output == actual
        correct+=1
      else
        wrong+=1
      end
    end

    tree.dnfprint("", 1) if print

    puts label
    puts "Correct: #{correct}, Wrong: #{wrong} => \
    #{100*correct.to_f/(correct+wrong).to_f}%"
    puts "Splits: #{tree.count}"
  end

  def self.buildAndTest(csvin, csvtest, print = false)
    tree = buildTree(csvin)

    # get data
    datas = []
    iteration = 0
    CSV.foreach(csvtest) do |row|
      iteration+=1
      next if iteration == 1 or iteration == 2
      datas << Datum.new(row)
      break if iteration >= MAX_ITERATIONS
    end

    dsplit = datas.in_groups(2)

    testOn(tree, dsplit[1], "ORIGINAL TREE:", print)

    # pruned tree once
    tree.prune(@@datas, dsplit.first) 
    testOn(tree, dsplit[1], "PRUNED TREE:", print)
    nil
  end

  def self.predict(train, validate, test, out)
    tree = buildTree(train)

    datas = []
    iteration = 0
    CSV.foreach(validate) do |row|
      iteration+=1
      next if iteration == 1 or iteration == 2
      datas << Datum.new(row)
      break if iteration >= MAX_ITERATIONS
    end

    tree.prune(@@datas, datas)

    CSV.open(out, "w") do |csv|
      iter = 0
      CSV.foreach(test) do |row|
        if iter < 2
          iter += 1
          next
        end

        d = Datum.new(row)
        o = tree.test(d)
        row[row.length - 1] = o
        csv << row
      end
    end
  end

  def self.buildTree(csvin, max_it = MAX_ITERATIONS)
    datas = []
    @@keys = []
    @@nom_choices = Hash.new(nil)
    @@output_choices = []

    iteration = 0
    CSV.foreach(csvin) do |row|
      iteration+=1
      if iteration == 1
        # take keys
        @@keys = row.map{ |k| k.gsub(' ','') }

        next
      elsif iteration == 2
        # set nominal stuff
        puts row.inspect
        @@keys.each_with_index do |k, ind|
          if row[ind].nil?
            @@nom_choices[k] = nil
          else
            @@nom_choices[k] = []
          end
        end
        next
      end

      @@keys[0...-1].each_with_index do |a, i|
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

      unless row.last == '?' or @@output_choices.include?(row.last)
        @@output_choices << row.last 
      end

      datas << Datum.new(row)
      break if iteration >= max_it
    end

    @@datas = datas

    puts "Finished reading data."

    tree = recursiveBuild(datas, @@keys[0...-1], Hash.new(0))

    @@leaves_printed = 0
    # tree.dnfprint("", 1)

    return tree
  end  
end

class Datum < TreeBuilder
  # contains one data instance from training set
  attr_accessor :vals
  attr_reader :output

  def initialize(vals)
    @vals = Hash.new(nil)
    # if vals.last == '?'
    #   @output = -1
    # else
    @output = vals.last.to_i
    # end
    @@keys[0...-1].each_with_index do |a, ind|
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
        child.test(data) if data.vals[@att] == @@nom_choices[@att][ind]
      end
    else # continuous
      if data.vals[@att].to_f < @thresh # > on one side, <= on oter
        @children.first.test(data)
      else
        @children[1].test(data)
      end
    end
  end

  def print(dots)
    str = "."*dots + "SPLIT ON #{@att}"
    if @nominal
      str += ": ("
      @@nom_choices[@att].each do |c|
        str+=c
        str+= "|"
      end
      puts str + ")"
    else
      puts str + ", thresh: #{@thresh}"
    end

    @children.each do |c|
      c.print(dots+1)
    end
  end

  def dnfprint(pstring, for_o)
    if @nominal
      @children.each_with_index do |c, ind|
        rule = "(#{@att} == #{@@nom_choices[@att][ind]})"
        rulestring = "#{pstring} AND #{rule}"
        c.dnfprint(rulestring, for_o)
      end
    else
      rule = "(#{@att} < #{@thresh})"
      rulestring = "#{pstring} AND #{rule}"
      @children.first.dnfprint(rulestring, for_o)
      rule = "(#{@att} >= #{@thresh})"
      rulestring = "#{pstring} AND #{rule}"
      @children[1].dnfprint(rulestring, for_o)
    end
  end

  def prune(datas, vdata)
    if @children.first.isLeaf # means all children are leaves
      # replace self with leaf that correctly classifies majority
      output_counts = Hash.new(0)

      datas.each do |d|
        output_counts[d.output]+=1
      end

      if datas.empty?
        # throw "Datas should not be empty at this step"
        return Leaf.new(@@output_choices.first)
      end

      return Leaf.new(output_counts.max_by{|k, v| v}.first)
    end

    # one deeper
    if @nominal
      @children.each_with_index do |child, ind|
        new_data = datas.select {|d| d.vals[@att] == @@nom_choices[@att][ind] }
        new_vdata = vdata.select {|d| d.vals[@att] == @@nom_choices[@att][ind] }

        if cprune = child.prune(new_data, new_vdata)
          self.checkForReplace(cprune, new_vdata, ind) 
        end
      end

    else
      # continuous
      new_data = datas.select do |d|
        d.vals[@att].is_a?(String) or d.vals[@att] < @thresh
      end
      new_vdata = vdata.select do |d|
        d.vals[@att].is_a?(String) or d.vals[@att] < @thresh
      end

      cprune = @children.first.prune(new_data, new_vdata)
      @children[0] = cprune if cprune
      if cprune = @children[0].prune(new_data, new_vdata)
        self.checkForReplace(cprune, new_vdata, 0)
      end

      # Second cild
      new_data = datas.select do 
        |d| !(d.vals[@att].is_a?(String)) and d.vals[@att] >= @thresh
      end
      new_vdata = vdata.select do |d|
        d.vals[@att].is_a?(String) or d.vals[@att] >= @thresh
      end
      
      if cprune = @children[1].prune(new_data, new_vdata)
        self.checkForReplace(cprune, new_vdata, 1) 
      end
    end

    return nil
  end

  def checkForReplace(cprune, vdata, idx)
    originalPercentage = self.getTestPercentage(vdata)
    oldNode = @children[idx]
    @children[idx] = cprune
    prunePercentage = self.getTestPercentage(vdata)

    if originalPercentage > prunePercentage
      @children[idx] = oldNode
    end
  end

  def getTestPercentage(vdata)
    correct = 0
    vdata.each do |v|
      correct+=1 if self.test(v) == v.output
    end
    correct.to_f/vdata.count.to_f
  end

  def isLeaf()
    false
  end

  def count
    count = 0
    @children.each {|c| count += c.count} if @children
    return count + 1
  end
end

class Leaf < Node
  # overloads test function to assign value after testing value
  def initialize(klassification)
    @klass = klassification
  end

  def test(data)
    @klass
  end

  def print(dots)
    puts "."*dots + "OUTPUT: #{@klass}"
  end

  def dnfprint(pstring, for_o)
    return if RESTRICT_PRINT_TO_16 && (@@leaves_printed > 16)
    if @klass == for_o
      puts "(#{pstring[4..-1]} ) OR\n\n" 
      @@leaves_printed+=1
    end
  end

  def prune(datas, vdata)
    return self
  end

  def isLeaf()
    true
  end
end

def t
  TreeBuilder.buildAndTest("btrain.csv", "bvalidate.csv")
end
