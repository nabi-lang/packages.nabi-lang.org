# csvq

Query CSV files with `select`, `where` and `group by`, from Nabi code or from the shell.

## Command line

```sh
nabi install --bin csvq
csvq 'select city, mean(temp) where year >= 2020 group by city' weather.csv
```

## Library

```nabi
let q = try csvq::parse("select name, score where score > 90");
println(csvq::run(q, try std::fs::read_to_str("scores.csv")));
```

Columns are typed from the first 1000 rows; a column with mixed values stays text. Built on [`table`](/packages/table).
