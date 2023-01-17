# Transient Record

`transient-record` is a gem to define temporary tables and Active Record models
for testing purposes. It's a great tool for testing **generic Active Record code
and libraries**.

The library was extracted from [active_record_doctor](https://github.com/gregnavis/active_record_doctor)
to allow reuse.

## Installation

Installing Transient Record is a two-step process.

### Step 1: Installing the Gem

You can include Transient Record in your `Gemfile`:

```ruby
gem "transient_record", group: :test
```

The above assumes it'll be used for testing purposes only, hence the `test`
group. However, if you intend to use the gem in other circumstances then you may
need to adjust the group accordingly.

If you'd like to use the latest development release then use the line below
instead:

```ruby
gem "transient_record", github: "gregnavis/transient_record", group: :test
```

After modifying `Gemfile`, run `bundle install`.

### Step 2: Integrating with the Test Suite

After installing the gem, Transient Record must be integrated with the test
suite. `TransientRecord.cleanup` must be called around every test case: before
(to prepare a clean database state for the test case) and after (to leave the
database in a clean state).

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
backed by them.

A table can be created by calling `create_table`: a thin wrapper around the
method of the same name in Active Record. The only difference is the method
in Transient Record implemented a fluent interface that allows calling
`define_model` on the return value.

For example, the statement below creates a table named `users` with two one
string column `name` and one integer column `age`:

```ruby
create_table :users do |t|
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
create_table :users do |t|
  # ...
end.define_model do
  validates :email, presence: true
end
```

Models are automatically assigned to constants in `TransientRecord::Models`. The
example above creates `TransientRecord::Models::User`, and is equivalent to:

```ruby
class TransientRecord::Models::User < ActiveRecord::Base
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
result in an error. Full support for parallelism **is** on the roadmap, so feel
free to report any errors and contribute updates.

## Author

This gem is developed and maintained by [Greg Navis](http://www.gregnavis.com).
