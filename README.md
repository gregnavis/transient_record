# Transient Record

`transient_record` is a gem to define temporary tables and Active Record models
for testing purposes. It's a great tool for testing **generic Active Record code
and libraries**.

The library was extracted from [active_record_doctor](https://github.com/gregnavis/active_record_doctor)
to allow reuse.

## Installation

Installing Transient Record is a two-step process.

### Step 1: Installing the Gem

You can include Transient Record in your `Gemfile`:

```ruby
# Add the following to use the most recent release:
gem "transient_record", group: :test

# Alternatively, you can use the most recent development version:
gem "transient_record", github: "gregnavis/transient_record", group: :test
```

Don't forget to run `bundle install`.

The above assumes it'll be used for testing purposes only, hence the `test`
group. However, if you intend to use the gem in other circumstances then you may
need to adjust the group accordingly.

### Step 2: Integrating with the Test Suite

After installing the gem, Transient Record must be integrated with the test
suite. `TransientRecord.cleanup` must be called around every test case: before
(to prepare a clean database state for the test case) and after (to leave the
database in a clean state).

**Transient Record is not prepared to work with parallel test suites, so ensure
tests that use it run sequentially.**

The snippet below demonstrates integrations with various testing libraries:

```ruby
# When using Minitest
class TransientRecordTest < Minitest::Test
  def before
    TransientRecord.cleanup
  end

  def after
    TransientRecord.cleanup
  end
end

# When using Minitest::Spec
class TransientRecordTest < Minitest::Spec
  before do
    TransientRecord.cleanup
  end

  after do
    TransientRecord.cleanup
  end
end

# When using RSpec
RSpec.describe TransientRecord do
  before(:each) do
    TransientRecord.cleanup
  end

  after(:each) do
    TransientRecord.cleanup
  end
end
```

## Usage

Transient Record can be used to create temporary tables and, optionally, models
backed by them. First, you need to define a Transient Record **context**.

A context is a module associated to a specific Active Record base class (like
`ActiveRecord::Base` or `ApplicationRecord`) that's used to connect to the
database and as a base class for transient models. Contexts are needed to
support multiple databases, as Active Record organizes database connections
around base classes. Consult [the Rails Guides](https://guides.rubyonrails.org/active_record_multiple_databases.html#setting-up-your-application) to learn more
about using Active Record with multiple databases.

**If you connect to only one database then you need just one context for
`ActiveRecord::Base`**.

A context is a Ruby module used to define transient tables and models. Here's
how a context for `ActiveRecord::Base` can be defined:

```ruby
Primary = TransientRecord.context_for ActiveRecord::Base
```

A table can be created by calling `create_table`: a thin wrapper around the
method of the same name in Active Record. The only difference is the method
in Transient Record implemented a fluent interface that allows calling
`define_model` on the return value.

For example, the statement below creates a table named `users` with two one
string column `name` and one integer column `age` using the `Primary` context
introduced above:

```ruby
Primary.create_table :users do |t|
  t.string :name, null: false
  t.integer :age, null: false
end
```

Refer to [Ruby on Rails API documentation](https://api.rubyonrails.org/classes/ActiveRecord/ConnectionAdapters/SchemaStatements.html)
for details.

In order to define a model backed by that table `define_model` can be called
**on the return value** of `create_table` with a block containing the model
class body. For example, to define

```ruby
Primary.create_table :users do |t|
  # ...
end.define_model do
  validates :email, presence: true
end
```

Models are automatically assigned to constants. In the example above, the user
model is assigned to `Primary::User` via code roughly equivalent to:

```ruby
class Primary::User < ActiveRecord::Base
  validates :email, presence: true
end
```

## Caveats and Limitations

Transient Record does **NOT** default to using temporary tables (created via
`CREATE TEMPORARY TABLE`) because of their second-class status in Active Record.
For example, temporary table are not listed by the `tables` method. For this
reason it was decided to use regular tables with an explicit cleanup step.

Transient Record may not work properly in parallelized test suites, e.g. if two
test workers attempt to create a table with the same name then it's likely to
result in an error.

## Author

This gem is developed and maintained by [Greg Navis](http://www.gregnavis.com).
