Class       = require('jsclass/src/core').Class

requires = require '../../requires'

_   = require 'prelude-ls'
lo  = require 'lodash'
require 'sugar'

PathResolver      = requires.pipe 'path_resolver'
BasePipe          = requires.pipe 'base'

# no need for a child validator :)
# any attachment is always to a parent - simply validate parent is valid for child
# no need to validate reverse relationship - is implicit :)
ParentValidator   = requires.pipe 'validator/parent'

# Must be on a model or attribute
ModelPipe = new Class(BasePipe,
  initialize: (@obj) ->
    @call-super @obj

  id: ->
    @id

  # TODO: Major refactoring needed. Split out in seperate modules or classes ^^

  model: ->
    switch arguments.length
    case 0
      throw new Error "Must take a name, a value (object) or a {name: value} as an argument"
    case 1
     @_add-model arguments[0]
    default
      throw new Error "Too many arguments, takes only a name, a value (object) or a {name: value}"

  _add-model: (arg) ->
    switch typeof arg
    case 'string'
      @_name-model arg
    case 'object'
      @_hash-model arg
    default
      throw new Error "Invalid Attribute pipe argument. Must a name (string) or an object (hash), was: #{arg}"

  _hash-model: (hash) ->
    key = _.keys(hash).first
    value = _.values(hash).first
    switch key
    case 'collection'
      throw new Error "No such thing as a Collection model. Try adding a collection directly instead, f.ex: .collection('users')"
    case 'model'
      # just ignore the model key and go with the value ;)
      @model value
    default
      #.model(administers: project)
      # should turn into:
      #.attribute('administers').model(project)

      # reuse existing attribute functionaility :)
      @attribute hash

  # attach an attribute pipe as a child
  attribute: ->
    switch arguments.length
    case 0
      throw new Error "Must take a name or a {name: value} as an argument"
    case 1
      @_add-attribute arguments[0]
    default
      throw new Error "Too many arguments, takes only a name (string) or an object (hash)"

  _add-attribute: (arg) ->
    switch typeof arg
    case 'string'
      @_name-attribute arg
    case 'object'
      @_hash-attribute arg
    default
      throw new Error "Invalid Attribute pipe argument. Must be a name (string) or an object (hash), was: #{arg}"

  _name-attribute: (name) ->
    attr-pipe = new AttributePipe name
    @attach attr-pipe

  _hash-attribute: (hash) ->
    key = _.keys(hash).first
    value = _.values(hash).first
    switch key
    case 'collection'
      # since attribute should only be for simple types, String, Int etc.
      @attach new CollectionPipe(value)

    case 'model'
      # since attribute should only be for simple types, String, Int etc.
      @attach new ModelPipe _clazz: value

    default
      # what should really happen here?
      # .model(administers: project)
      # should turn into:
      # .attribute('administers').model(project)
      @attach new AttributePipe(key).attach @_pipe-from(value)

    _pipe-from: (value) ->
      switch typeof value
      case 'object'
        new ModelPipe value
      case 'array'
        new CollectionPipe value

  valid-parents:
    * 'container'
    * 'collection'
)

module.exports = ModelPipe