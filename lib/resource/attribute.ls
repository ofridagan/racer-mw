Class       = require('jsclass/src/core').Class

require = require '../../requires'

requires.resource 'base'

AttributeResource = new Class(BaseResource,
  # value-object
  initialize: (@value-object)

  commands:
    scope:
      * 'get'
      * 'set'
      * 'ref'
      * 'remove-ref'
    number:
      * 'inc'
    string:
      * 'string-insert'
      * 'string-remove'
)

module.exports = AttributeResource