SPLIT_MAX = 4

def median(ary)
  # from http://stackoverflow.com/questions/21487250/find-the-median-of-an-array
  mid = ary.length / 2
  sorted = ary.sort
  ary.length.odd? ? sorted[mid] : 0.5 * (sorted[mid] + sorted[mid - 1])
end

class Datum
  # contains one data instance from training set
  attr_accessor :vals

  def initialize(attrs, vals, out)
    @vals = Hash.new(nil)
    attrs.each_with_index do |d, ind|
      @vals[d] = vals[ind] unless vals[ind] == '?'
    end
    @vals['output'] = out
  end

  def output
    @vals['output']
  end
end

class Node
  # Either assigns classification or passes or tests for other nodes
  # Sends to one child after testing value

  def intialize(att, thresh = nil)
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

  def test(data, nom_choices)
    if @nominal
      @children.each_with_index do |child, ind|
        # TODO: this doesn't work:
        child.test(data, nom_choices) if data[@att] == nom_choices[@att][ind]
      end
    else
      if data[@att] > @thresh # > on one side, <= on oter
        @children.first.test(data)
      else
        @children[1].test(data, nom_choices)
      end
    end
  end


  def print


  end
end

class Leaf < Node
  # overloads test function to assign value after testing value

  def test



  end
end

def buildTree(csv, atts, nominal)
  # attributes = [attribute-names]
  # nominal = {k = attribute-name, val = t or f}


  # for keeping track of num splits on non-nominal attributes
  numSplits = Hash.new(0)

end

def recursiveBuild(datas, atts_left, numSplits, nominals)
  # nominals = {att => [c1, c2, c3], att => nil, att => [c1, c2], att => nil}

  # return Leaf if no splits left
  all_the_same = datas.map(&:output).all?(datas.first.output)
  # return Leaf if all_the_same

  best_entr = 0
  best_thresh = nil
  best_att = nil
  examples = datas.count

  atts_left.each do |a|
    if not nominals[a]
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
      median = median(datas.map(&:output))
      entropy = -Math.log2(.5)
    end

    if entropy >= best_entr
      best_entr = entropy
      best_att = a
      best_thresh = median if median
    end
  end

  if not nominals[best_att]
    atts_left = atts_left - [best_att] if (numSplits[best_att] +=1) >= SPLIT_MAX
    n = Node.new(best_att, best_thresh)
  else
    atts_left = atts_left - [best_att]
    n = Node.new(best_att)
  end

  # split datas and recurse to add children
  # kids array goes lowest to igest, left to rigt in nomCoices
  kids = []
  if nominals[best_att]
    nominals[best_att].each do |possible_val|
      datac = datas.select { |d| d[best_att] == possible_val }
      kids << recursiveBuild(datac, atts_left, numSplits, nominals)
    end
  else
    datac1 = datas.select { |d| d[best_att] < best_thresh }
    datac2 = datas.select { |d| d[best_att] >= best_thresh }
    kids = [recursiveBuild(datac1, atts_left, numSplits, nominals),
            recursiveBuild(datac2, atts_left, numSplits, nominals)]
  end

  n.addChildren(kids)

  return n
end
