# ico-fund-prototype

![](https://travis-ci.org/mixbytes/icoplate-fund-prototype.svg?branch=master)

Prototype of ICO fund governed by the investors

Install dependencies:
```bash
npm install
```

Build and test:
```bash
# start testrpc if not already running:
testrpc -u 0 -u 1 -u 2 -u 3 -u 4 -u 5 --gasPrice 2000 &

truffle compile && truffle test
```
