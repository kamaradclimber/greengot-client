# Client

Warning: since https://trello.com/c/d7RdmKVs, report can be received in csv format. I will no longer maintain the solution described below.
However, the script `greengot_csv2qif.rb` can still be useful to convert CSV from greengot to qif format.


This is a very small demonstration client for greengot bank.
I'm using it to extract my transactions and import them in Linxo using QIF format

There are warnings in the code, read them to understand the risks.

# Api description

Here is what I understood from the api by exploring interactions of the Android app

- POST https://api.green-got.com/v2/signin
	- requires a header `x-mobile-unique-id` which is generated locally (any fits?) that will be reused over and over
	- content-type is application/json
	- body is `{"email": "<the email>"}`
	- response is json with a single field `{"hasNeverActivatedCard": false }` (nice double-negation)
	- at this point we should receive an email with validation code
- POST https://api.green-got.com/v2/check-login-code
	- we still send the `x-mobile-unique-id` header
	- request is json `{"email: <the email>, "oneTimeCode": "<a string which is a number>", "panLast4Digits": "<a string which are the 4 last digits of credit card>"}`
	- response is a long json with personal identification (card info, account info, postal address, some personal communication preferences). The main info is in field `idToken` which will be reused later.
	- answers can be something like `{"name": "invalidLast4Digits", "message": "Invalid last 4 digits"}` which helps to understand error if any.
- GET https://api.green-got.com/info-box
	- we still send the `x-mobile-unique-id` header
	- we also send the `authorization` header with `Bearer <the id token from previous step>`
	- response is empty
- GET https://api.green-got.com/user
	- same header `x-mobile-unique-id` and `authorization`
	- response is json and contains roughly the same info than /check-login-code, minus idToken
	- if another device has registered, answer will be 401.
- GET https://api.green-got.com/v2/transactions?limit=20
	- example: `curl -H 'x-app-version: 1.7.3' -H 'authorization: Bearer xxxx' -H 'x-mobile-unique-id: yyyyy' --compressed -H 'user-agent: okhttp/4.10.0' 'https://api.green-got.com/v2/transactions?limit=20&startDate=2023-04-06T00:15:01.000Z&cursor=abcdef'`
	- query parameters are
		- limit: <int>
		- startDate: <a date> with format similar to `2023-04-06T00:15:01.000Z`
		- cursor: <a cursor> fetched from previous transactions request
	- still same headers as usual
	- response is json with the following fields:
		- nextCursor: <string>
		- nextStartDate: <date>
		- transactions: an array of transaction
			-
			  ```
			  {
			              "acceptance": {
			                  "method": "CHIP"
			              },
			              "amount": {
			                  "currency": "EUR",
			                  "value": 874
			              },
			              "co2Comparables": {
			                  "description": "Equivalent à 392,4 km en train"
			              },
			              "co2Explanation": {
			                  "description": "Certaines transactions sont difficiles à catégoriser et sont donc considérées comme de la « consommation générale ». 🤔 On peut y trouver des achats comme des jeux 🎲 des fleurs 💐 ou encore des produits ménagers 🧽 \n\nDans ce cas nous les classifions de la consommation générale car il ne nous pas possible de déterminer s'il s'agit d'un achat alimentaire ou non alimentaire. Le facteur est donc calculé en divisant les émissions moyennes de Co2 d'un Français par le revenu médian annuel. 🇫🇷\n\nCe n’est pas idéal mais c’est un début, nous travaillons encore à affiner ce chiffre, notamment pour vous donner la possibilité de préciser le type de produits (viande, légumes, cosmétiques, bien manufacturés, ...) ce qui impacte fortement les émissions associées. 💪"
			              },
			              "co2Footprint": 3924,
			              "counterparty": "CARREFOUR EXP",
			              "createdAt": "2023-04-15T10:18:55.000Z",
			              "direction": "DEBIT",
			              "id": "xxxxxxxxxxxxxxxx",
			              "status": "AUTHORISED",
			              "type": "CHIP"
			          },
			  ```
		- acceptance methods:
			- ECOMMERCE: internet payment
			- CHIP: card payment
			- CONTACTLESS_CARD: without pin code
			- DIRECT_DEBIT: direct debit operated by a provider (electricity provider for instance)
			- MANUAL: looks similar to direct_debit
			- SEPA: money transfert
			- UNKNOWN: used by greengot fee subscription

