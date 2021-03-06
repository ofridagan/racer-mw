# Design

The following some design ideas/thoughts and conclusions as we go deeper down the "rabbit hole" :)

## Lessons learned

Operations fall into the following categories

**on a Document within a collection**

```
users.1.user
users.2.user
```

**on a Document within a collection of another document**

```
users.1.user.admins.1.admin-user
```

Should we validate as to whether this admin-user is valid for the user who owns the collection?

```
users.1.user.admins.1.admin-user.tags = ['abra', 'ca', 'dabra']
```

What if we move or pop an element from the tags collection (simple String values).
Should we validate with respect to the `admin-user` container? Yeah...

## More advanced pipelining

From the above analysis we can see the following conclusions taking shape...

We might need two middleware pipelines.

- container-stack
- item-stack

For some operations, it is the container model object that determines whether the operation is allowed
For others it is the item itself, being inserted into some named collection (not a model object).

The container-stack will always be simple, since it will never have to bother about marshalling or decoration.
It will thus only concern authorization and validation of the operation.
Most often it will likely be a "by-pass" operation... ;)

*Example*

Add new Document (model obj) to an attribute (List) of container Document (model obj).

### Adv. Validation

The validation could take the container object, the attribute and the item obj and validate whether
the container obj allows this item obj to be inserted into the list.
This could be based either on the type of container and item object or even on the state of the container object (which
could be set up to live-update subscribe to changes in the model).

`mw-stack('container').validate container: container, attribute: attribute, item: item`

Of course this could later be optimized to a nicer DSL if need be

`mw-stack('container').validate-on(container).add-to(attribute, item)`

This can be vastly simplified by employing a hierachical model to reflect this
and then have each level "do its thing". Then each layer will have at most one mw-stack!

### Adv. Authorization

`mw-stack('container').authorize.can 'add', data: item, ctx: {container: container, attribute: attribute}`

The key is to allow the developer to configure this as required while facilitating certain common patterns.
We should not apply too strict conventions, at least until we have uncovered typical repetitive usage patterns
that can be encapsulated.

```
current-user.$save!
current-user.$set name: 'unknown'

# should try to add to 'projects'
current-user.$add(project)

current-user.$set current-project: project
current-user.$get 'project', {status: 'done'}

current-user.$add('my-projects', project)
current-user.$delete!

admin-user = {
  name: 'Kris'
  role: 'admin'
  clazz: 'user'
}
```

To chain simply use the following DSL

```livescript
users-pipes = collection('users')
    .model(admin-user)
    .model(guest-user)
```


```livescript
pipes.admin-user = container('_page')
  .attribute('current')
    .model(admin-user)

# using add
pipes.admin-user = container('_page')
  .attribute('current').add
    .model(admin-user).add
```

To execute resource functions use `$res` to get the connected resource or use a `$` function directly on the pipe.

`pipes.admin-user.$res.set role: 'guest'`

Using shortcut `$set` directly on pipe:

`pipes.admin-user.$set role: 'guest'`

Lets make a query...

```livescript
# get all admin users since past 3 days
pipes.admin-user.$query date: {$gte: days(3).before(new Date) }}
```

The Resource should contain the following

```livescript
resources.admin-user = {
  value-object: {
    name:   'Kris'
    role:   'admin'
    _clazz: 'user'
  }

  $pipe: pipe
  $resource:
    $save: ->
      @$set @value-object

    $set: (value-hash) ->
      # ...
    $get: (model, query) ->
      # ...
    $delete: ->
      # ...
}
```

A resource should normally be created from a Pipe.

collection('users').

In the following we use `admin-user` both as an "end" pipe and a container "pipe" (better term than pipe?).
We should not share the reference, so the call to `$p` must be a constructor, and `admin-user` must be cloned by value
 or just the relevant values extracted when used as a container.

So the call to `.$p(model: project)` on the model obj for `admin-user` must turn it into a container, without affecting
the `$pipes.admin.user`. In turn, as a container, the mw-stack should be changed, so as to not marshal or decorate.
the Validator step should also be different, such that it sends something like: `container: @, data: @.$child`


```livescript
$pipes.admin.user     = users-col.$a(model: admin-user)
$pipes.admin.project  = users-col.$a(model: admin-user).$a(model: project)
```

So we can see we need a `$child` for the `admin-user-container` that points to the next item in the pipe.
To avoid too pipe-specific properties/methods in the core data/behavior namespace, we should create
 a namespace `$pipe` to contain them.

```livescript
admin-user-container = {
  $pipe:
    $type:  'container'
    $parent: current-admin-path
    $child: project

  $resource:
    $class: 'user'
}

```

### $p and $pipeline constructors

Here we design the $p and $pipeline for chaining

```livescript
# args: Hash - key = type, value = object
# creates a new pipe of the given type from the value
$p = (hash) ->
  parent = @
  keys = _.keys(hash)
  throw Error "Must only have one key/value entry, was #{keys}"
  type = keys.first
  obj = hash[type]
  @$pipe.child = new PipeFactory(obj, parent: parent, type: type).create-pipe

$pipe = (hash) ->
  keys = _.keys(hash)
  throw Error "Must only have one key/value entry, was #{keys}"
  type = keys.first
  new PipeFactory(hash[type], type: type).create-pipe
```

And now the pipe factory :)

```livescript
PipeFactory = new Class(
  initialize: (@value-object, @options = {}) ->
  @type     = @options.type
  @parent   = @options.parent

  create-pipe: ->
    @value-object.$pipe = pipe!
    @value-object.$p = $p # from local Node module scope
    @value-object

  set-mw: ->
    switch @type
    case 'model'
    default
      @value-object.$resource.mw-stack.remove types: ['validator', 'authorizer']

  pipe: ->
    walk = (meth, steps) ->
        if steps > 10
          throw Error "You should NEVER have more than 10 pipes in a model pipeline!!!"
        step = 0
        location = @[meth]!
        while step < steps and locations isnt void
          location = location.@[meth]!
        location
    {
      $type   : @type
      $parent : @parent
      $child  : void
      $prev   : (steps) ->
        walk '$parent', steps
      $next    : (steps) ->
        walk '$child', steps
      $root: ->
        walk '$parent', 9
      $end: ->
        walk '$child', 9

      $value-object: @value-object
      $calc-path: ->
        new PathResolver @§value-object
    }
)

module.exports = PipeFactory
```

Sure looks pretty sweet and workable!

The `project` is an "end-pipe" with the parent resource-pipe (container) `admin-user`

```livescript
project = {
  $pipe
    $type:  'resource'
    $parent: admin-user
    $child  : void
  $resource:
    $class: 'project'
}
```

### DSL optimization

`users-col.$p(model: admin-user).$p(model: project)`

The top levels are always some sort of containers. They only have different behavior depending on whether
they are a full resource-pipe or just a simple-pipe. Their position in the pipeline determines their relative behavior
with respect to the pipeline. So really no need for the `type` part
Can be simplified to:

`$pipe('users').$p(admin-user).$p('deeper.path').$p(project)`

We should still allow the type variant for decorative/debugging
purposes (and better conceptual understanding of the code, i.e a clearer DSL).

### Path resolution

```livescript
PathResolver = new Class(
  initialize: (@model-obj) ->
    @collection = @pluralize model-obj.$resource.$class
    @parent = model-obj.$pipe.$parent

  obj-path: ->
    @collection

  parent-path: ->
    if @parent? then @parent.$pipe.$calc-path else void

  full-path: ->
    [@parent-path, @obj-path].compact!.join '.'
)
``

Remember, a piped `project` looks like this...

```livescript
project = {
  # ...
  $pipe:
    # ...
    $value-object: project
    $calc-path: ->
      new PathResolver @$value-object
```

Now that we can calculate the paths at any step, we need to implement the main Resource methods.
However first we will look at how Validation and Authorization fits in with Pipes and Resources...

### Validation

When we validate, we should validate the action with respect to all the parents of the end-pipe in question.
They also are allowed have a say whether the data is valid in that given context.
However mostly the parents don't care and leave the child to do its own thing as long as it
stays within its own boundaries... mostly it is only the closest parent who gives a damn (in this context!)

### Authorization

For authorization we should also send in the list of parents as part of the context in which to authorize in.
The permit (or other authorization) is then free to use this information to authorize.

We need a PathResolver to resolve the full path at each step in the hierarchy.
This way we extract this functionality (Single Responsibility) and avoid cluttering each Resource with source logic...

Note that in both cases, if the parent is a model-object (or resource), it could be set to *live-update*.
Then when doing validation/authorization we can be sure it is with respect to its latest state and not some old state
no longer "in touch" with the server state. Perhaps we should enforce this somehow (or at least make it default)

## Enable/Disable validation and authorization

In some (most?) cases, there is no need to consult the parent(s) for Auth and/or Val.
It should be easy to disable Auth and Val for any "piece in the puzzle".

```livescript
# turn off validation
users-col.$mw.off 'v'
users-col.$mw.off! # turn all mw off
users-col.$mw.on! # turn all mw on

users-col.$a(model: admin-user).$mw.off!.$a(...)
```

## Marshalling

We have added a few `$` prefixed properties and methods to the Resouce model.
You don't want these values to be stored in the DB. So the marshalling (marshal-mw) should ensure that any `$` value
is always discarded and then they will be put back on by the Resource decorator :)
At least it should always discard `$resource` and `$pipe`.

### $set current model object as-is

set with current values

```livescript
$save: ->
  $set @
```

### $set model object

Perform should be responsible for generating the path to be used
It should first authorize, validate and marshal and then use $calc-path to
calculate the full path (via PathResolver)

```livescript
$set: (value-hash) ->
  @perform 'set', value-hash
```

### $set attribute with value

```livescript
$set: (attribute, value) ->
  vhash = {}; vhash[attribute] = value
  $set vhash
```

same as $set but using 'if-null' method, setting only if null (not present yet!)

```
$set-null: (attribute, value, opts) ->
  @perform 'if-null', ...
```

### $get model

Should first authorize, then decorate (if get value). Also allow subscript and live-update (ref)
See *CrudGet* ;)

```livescript
$get: (model)
  @perform 'get', @get-for(model)
```

### $get query

Query under current path..

```livescript
$get: (q: query)
  @perform 'get', query
``

### Delete

Should first authorize

```livescript
$delete: (path) ->
  @perform 'del'
```

## Extras

### $inc attribute

Should first authorize and validate (but only if container is synced?)

```livescript
$inc: (attribute, path) ->
  @perform 'increment', attribute
```

### $push model-obj

If parent is a collection. Note that `@value-object!` is necessary to get the real value, as we are calling
 from withing the context of a `Resource`.

```livescript
$push: ->
  @perform 'push', @value-object!
```

As we see here, path or perform should create a new Execution object,
decoupled from the Resource itself, only referencing it

Path coupled with the current path should add up to path that points to collection
If no value as 2nd arg, then use self (model obj)

```livescript
$push: (path) ->
  @path(path).perform 'push', @value-object!
```

If no value as 2nd arg, then push this

```livescript
$push: (path, value) ->
  @path(path).perform 'push', @value-object!
```

values can be a list of args or an array

```livescript
$push: (path, values) ->
  @path(path).perform 'push', values.flatten!.compact!
```

To avoid cluttering the model with all these Resource methods, we should have them in one place

```livescript
user = {
  $class: 'user'
  $res: ->
    @$resource ||= new Resource @
}

user.$res!.save!
user-res = user.$res!
user-res.save!
user-res.del!
```

or even

`res = $resource(user).$save!.has(email: email)`

Where `$resource` returns the resource of the user

## Resource: advanced chaining DSL

`$resource(user).$set(age: 27).$push('projects', project).$delete('project').from('archived-projects').where('oldest', 10)`

Let's attempt designing the Resource now!

```livescript
Resource = new Class(
  # value-object
  initialize: (@value-object)

  $save: ->
    @$set @value-object

  $set: ->
    # clever args handling...
)
```

We must combine multiple setters into one..

```livescript
  $set: (value-hash) ->
    @perform 'set', value-hash

  $set: (attribute, value) ->
    vhash = {}; vhash[attribute] = value
    $set vhash

  $set: ->
    #...
```

We can subclass `RacerSync` to get @perform, however subclassing is a little too "heavy-handed" as we get too much mixed into
the Resource. Baaad! Better to

```livescript
Resource = new Class(RacerSync,
  $set: ->
    @$scoped = switch arguments.length
    case 0
      @$set @value-object
    case 1
      @perform 'set', arguments[0]
    case 2
      vhash = {}
      vhash[arguments[0]] = arguments[1]
      @$set vhash
    default
      throw Error "Too many arguments #{arguments.length}, must be 0-2 for $set"
```

Better like this:

```livescript
Resource = new Class(
  sync: ->
    @my-sync ||= new RacerSync @

  perform: ->
    @sync!.perform arguments
```

Perhaps we could even use `Forwardable` from *jsclass* ?

Pure Awesomeness!!

## Live updates and subscriptions

And how about live updates (refs) and subscriptions to model change events?

Derby docs [subscriptions](http://derbyjs.com/#subscriptions)

The `subscribe`, `fetch`, `unsubscribe`, and `unfetch` methods are used to load and unload data from a model.
These methods don’t return data directly. Rather, they load the data into the model.
The data are then accessed via model getter methods.

`subscribe` and `fetch` both return data initially, but subscribe also registers with *PubSub* on the server to
receive ongoing updates as the data change.

```
model.subscribe ( items..., callback(err) )
model.fetch ( items..., callback(err) )
model.unsubscribe ( items..., callback(err) )
model.unfetch ( items..., callback(err) )
```

`items`: Accepts one or more subscribable items, including a path, scoped model, or query

`callback`: Calls back once all of the data for each query and document has been loaded or when an error is encountered

"subscribable items, including a path, scoped model, or query"

To make it easier, we should always return and use scoped models.

To access it `user.$resource.$scoped` or shortcut, simply `user.$scoped!`, same with `user.$alive` for the
live updated model.

```
user = {
  $scoped: ->
    $resource.$scoped
  $alive: ->
    $resource.$alive

  $resource:
    $perform: (action, path, args...) ->
      subject = if path then @$calc-path(path) else @$scoped
      @sync.perform action, subject, args

    update-model: (live-obj) ->
      new LiveDecorator(@value-object).decorate live-obj

    $alive: void
    $scoped: void
    $subscribe: (cb, path) ->
      @perform 'subscribe', path, cb

    # model.ref path, to
    $live: (path)->
        $alive = @perform 'ref', path
        @update-model($alive)

    $remove-live: (path) ->
      $alive = @perform 'refRemove', path

    $get: (path) ->
      @perform 'get', path

    $at: (id) ->
      @id ||= id
      throw Error "No id set for #{@collection}" unless @id
      @$scoped = @perform 'at', @id

    save: ->
      # ...

    $set: ->
      # ...
}
```

So now we can do `user.$resource.$subscribe` and have `scoped` models with *live update*.

Here is a simple (default) implementation of `LiveDecorator`, used to update the value-object
with the incoming "live data" from the data store.

```livescript
LiveDecorator = new Class(
  initialize: (@vo)

  decorate: (live-obj) ->
    lo.extend @vo, live-obj

)
```



## Resources that are not value objects

Note: A resource can also be part of a piped `collection`, `attribute` or `path`.
In that case it operates just the same, except there is no value-object for the resource.
Also there is no middleware stack. Thus it is a simple-resource.

## Reusable "smart" queries

Note this part:

`$delete('project').from('archived-projects').where('oldest')`

Here we are taking advantage of a named query.

```livescript
user.$resource.$queries.add = {
  oldest: -> {date: {$gte: Date() + days(3).before('today')} }
}

user.$resource.$queries =
  oldest: (num) ->
    {date: {$gte: Date() + days(3).before('today')} }.extend @limit(num)

  youngest(num): ->
    { $sort: {asc: 'age'} }.extend @limit(num)

  limit: (num) ->
    { $limit: num }
```

Pretty awesome!!!

Please add more thoughts/ideas... :)
