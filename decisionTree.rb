class Data
  # contains a data instance from training set
  attr_accessor :vals

  def initialize(attrs, vals)
    @vals = Hash.new(nil)
    attrs.each_with_index do |d, ind|
      @vals[d] = vals[ind] unless vals[ind] == '?'
    end
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

  def addChildren()

  end

  def test(data, nom_choices)
    if @nominal
      @children.each_with_index do |child, ind|
        child.test(data, nom_choices) if data[@att] == nom_choices[@att][ind]
      end
    else
      if data[@att] > @thresh
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

def buildTree(csv, attributes, nominal)
  # attributes = [attribute-names]
  # nominal = {k = attribute-name, val = t or f}

  # for keeping track of num splits on non-nominal attributes
  numSplits = Hash.new(0)


  # while training not perfectly classified

  # pick best attribute

  # split it (create new node)






  # end
end
