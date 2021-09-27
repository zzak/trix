import Trix from "trix/global"
import TrixObject from "trix/core/object" # Don't override window.Object
import Text from "trix/models/text"

import { arraysAreEqual, spliceArray, getBlockConfig, getBlockAttributeNames, getListAttributeNames } from "trix/core/helpers"

export default class Block extends TrixObject
  @fromJSON: (blockJSON) ->
    text = Text.fromJSON(blockJSON.text)
    new this text, blockJSON.attributes

  constructor: (text, attributes) ->
    super(arguments...)
    @text = applyBlockBreakToText(text || new Text)
    @attributes = attributes || []

  isEmpty: ->
    @text.isBlockBreak()

  isEqualTo: (block) ->
    super.isEqualTo(block) or (
      @text.isEqualTo(block?.text) and
      arraysAreEqual(@attributes, block?.attributes)
    )

  copyWithText: (text) ->
    new Block text, @attributes

  copyWithoutText: ->
    @copyWithText(null)

  copyWithAttributes: (attributes) ->
    new Block @text, attributes

  copyWithoutAttributes: ->
    @copyWithAttributes(null)

  copyUsingObjectMap: (objectMap) ->
    if mappedText = objectMap.find(@text)
      @copyWithText(mappedText)
    else
      @copyWithText(@text.copyUsingObjectMap(objectMap))

  addAttribute: (attribute) ->
    attributes = @attributes.concat(expandAttribute(attribute))
    @copyWithAttributes(attributes)

  removeAttribute: (attribute) ->
    {listAttribute} = getBlockConfig(attribute)
    attributes = removeLastValue(removeLastValue(@attributes, attribute), listAttribute)
    @copyWithAttributes(attributes)

  removeLastAttribute: ->
    @removeAttribute(@getLastAttribute())

  getLastAttribute: ->
    getLastElement(@attributes)

  getAttributes: ->
    @attributes.slice(0)

  getAttributeLevel: ->
    @attributes.length

  getAttributeAtLevel: (level) ->
    @attributes[level - 1]

  hasAttribute: (attributeName) ->
    attributeName in @attributes

  hasAttributes: ->
    @getAttributeLevel() > 0

  getLastNestableAttribute: ->
    getLastElement(@getNestableAttributes())

  getNestableAttributes: ->
    attribute for attribute in @attributes when getBlockConfig(attribute).nestable

  getNestingLevel: ->
    @getNestableAttributes().length

  decreaseNestingLevel: ->
    if attribute = @getLastNestableAttribute()
      @removeAttribute(attribute)
    else
      this

  increaseNestingLevel: ->
    if attribute = @getLastNestableAttribute()
      index = @attributes.lastIndexOf(attribute)
      attributes = spliceArray(@attributes, index + 1, 0, expandAttribute(attribute)...)
      @copyWithAttributes(attributes)
    else
      this

  getListItemAttributes: ->
    attribute for attribute in @attributes when getBlockConfig(attribute).listAttribute

  isListItem: ->
    getBlockConfig(@getLastAttribute())?.listAttribute

  isTerminalBlock: ->
    getBlockConfig(@getLastAttribute())?.terminal

  breaksOnReturn: ->
    getBlockConfig(@getLastAttribute())?.breakOnReturn

  findLineBreakInDirectionFromPosition: (direction, position) ->
    string = @toString()
    result = switch direction
      when "forward"
        string.indexOf("\n", position)
      when "backward"
        string.slice(0, position).lastIndexOf("\n")

    result unless result is -1

  contentsForInspection: ->
    text: @text.inspect()
    attributes: @attributes

  toString: ->
    @text.toString()

  toJSON: ->
    text: @text
    attributes: @attributes

  # BIDI

  getDirection: ->
    @text.getDirection()

  isRTL: ->
    @text.isRTL()

  # Splittable

  getLength: ->
    @text.getLength()

  canBeConsolidatedWith: (block) ->
    not @hasAttributes() and
      not block.hasAttributes() and
      @getDirection() is block.getDirection()

  consolidateWith: (block) ->
    newlineText = Text.textForStringWithAttributes("\n")
    text = @getTextWithoutBlockBreak().appendText(newlineText)
    @copyWithText(text.appendText(block.text))

  splitAtOffset: (offset) ->
    if offset is 0
      left = null
      right = this
    else if offset is @getLength()
      left = this
      right = null
    else
      left = @copyWithText(@text.getTextAtRange([0, offset]))
      right = @copyWithText(@text.getTextAtRange([offset, @getLength()]))
    [left, right]

  getBlockBreakPosition: ->
    @text.getLength() - 1

  getTextWithoutBlockBreak: ->
    if textEndsInBlockBreak(@text)
      @text.getTextAtRange([0, @getBlockBreakPosition()])
    else
      @text.copy()

  # Grouping

  canBeGrouped: (depth) ->
    @attributes[depth]

  canBeGroupedWith: (otherBlock, depth) ->
    otherAttributes = otherBlock.getAttributes()
    otherAttribute = otherAttributes[depth]
    attribute = @attributes[depth]

    attribute is otherAttribute and
      not (getBlockConfig(attribute).group is false and
      otherAttributes[depth + 1] not in getListAttributeNames()) and
      (@getDirection() is otherBlock.getDirection() or otherBlock.isEmpty())

  # Block breaks

  applyBlockBreakToText = (text) ->
    text = unmarkExistingInnerBlockBreaksInText(text)
    text = addBlockBreakToText(text)
    text

  unmarkExistingInnerBlockBreaksInText = (text) ->
    modified = false
    [innerPieces..., lastPiece] = text.getPieces()
    return text unless lastPiece?

    innerPieces = for piece in innerPieces
      if piece.isBlockBreak()
        modified = true
        unmarkBlockBreakPiece(piece)
      else
        piece

    if modified
      new Text [innerPieces..., lastPiece]
    else
      text

  blockBreakText = Text.textForStringWithAttributes("\n", blockBreak: true)

  addBlockBreakToText = (text) ->
    if textEndsInBlockBreak(text)
      text
    else
      text.appendText(blockBreakText)

  textEndsInBlockBreak = (text) ->
    length = text.getLength()
    return false if length is 0
    endText = text.getTextAtRange([length - 1, length])
    endText.isBlockBreak()

  unmarkBlockBreakPiece = (piece) ->
    piece.copyWithoutAttribute("blockBreak")

  # Attributes

  expandAttribute = (attribute) ->
    {listAttribute} = getBlockConfig(attribute)
    if listAttribute?
      [listAttribute, attribute]
    else
      [attribute]

  # Array helpers

  getLastElement = (array) ->
    array.slice(-1)[0]

  removeLastValue = (array, value) ->
    index = array.lastIndexOf(value)
    if index is -1
      array
    else
      spliceArray(array, index, 1)
