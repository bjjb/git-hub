# rest

Sub-modules for `GitHub::REST`.

| File                    | Purpose                                    |
|-------------------------|--------------------------------------------|
| `paginator.cr`          | Abstract paginator and cursor base classes |
| `array_paginator.cr`    | Paginator for bare JSON array responses    |
| `object_paginator.cr`   | Paginator for wrapper object responses     |
| `rate_limit.cr`         | Rate limit state parsed from headers       |
| `error.cr`              | REST error with status and body            |
