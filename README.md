# Kind

## Overview

Kind is designed to be an efficient and easy-to-use tool for proof verification. Its rewrite in Haskell aims to improve performance and code maintainability.

## Features

- Minimalist proof verification
- Simple command-line interface
- Support for various types of proofs and theorems

## Requirements

To use Kind, you will need:

- GHC (Glasgow Haskell Compiler)
- Cabal (build system for Haskell)

## Installation

1. Clone the repository:

   ```sh
   git clone https://github.com/HigherOrderCO/Kind.git
   cd kind
   ```

2. Install dependencies and compile the project:

   ```sh
   cabal build
   ```

## How to Use

After installation, you can use the `kind` command to verify or execute terms. For example:

  ```sh
  kind check your_proof_file.kind
  ```

## Usage

Kind can be used with the following commands:

- `kind check`: Checks all .kind files in the current directory and subdirectories
- `kind check <name|path>`: Type-checks all definitions in the specified file
- `kind run <name|path>`: Normalizes the specified definition
- `kind show <name|path>`: Stringifies the specified definition
- `kind to-js <name|path>`: Compiles the specified definition to JavaScript
- `kind deps <name|path>`: Shows immediate dependencies of the specified definition
- `kind rdeps <name|path>`: Shows all dependencies of the specified definition recursively
- `kind help`: Shows the help message


## Grammar

The grammar of Kind is defined as follows:

```bnf
<Name> ::= <alphanumeric-string>

<Numb> ::= <json-number-literal>

<Term> ::=
  | ALL: "∀(" <Name> ":" <Term> ")" <Term>      # Universal quantifier (also accepts "@")
  | LAM: "λ" <Name> <Term>                      # Lambda abstraction (also accepts "@")
  | APP: "(" <Term> <Term> ")"                  # Function application
  | ANN: "{" <Name> ":" <Term> "}"              # Type annotation
  | SLF: "$(" <Name> ":" <Term> ")" <Term>      # Self-referential type
  | INS: "~" <Term>                             # Instance marker
  | DAT: "#[" <Term>* "]" "{" (<Ctor>)* "}"     # Algebraic data type definition
  | CON: "#" <Name> "{" <Term>* "}"             # Constructor application
  | SWI: "λ{0:" <Term> "_:" <Term> "}"          # Switch expression (also accepts "@")
  | MAT: "λ{" ("#" <Name> ":" <Term>)* "}"      # Pattern matching (also accepts "@")
  | REF: <Name>                                 # Reference (variable)
  | LET: "let" <Name> "=" <Term> <Term>         # Let binding
  | SET: "*"                                    # Type universe
  | NUM: <Numb>                                 # Numeric literal
  | OP2: "(" <Oper> <Term> <Term> ")"           # Binary operation
  | TXT: '"' <string-literal> '"'               # Text literal
  | HOL: "?" <Name> ("[" <Term> ("," <Term>)* "]")? # Hole (with optional context)
  | MET: "_" <Numb>                            # Meta variable

<Ctor> ::=
  | "#" <Name> <Tele>                         # Data constructor with telescoped parameters

<Tele> ::=
  | "{" (<Name> ":" <Term>)* "}" ":" <Term>   # Named parameters with types and return type

<Oper> ::=
  | "+"   # Addition
  | "-"   # Subtraction
  | "*"   # Multiplication
  | "/"   # Division
  | "%"   # Modulo
  | "<="  # Less than or equal
  | ">="  # Greater than or equal
  | "<"   # Less than
  | ">"   # Greater than
  | "=="  # Equal
  | "!="  # Not equal
  | "&"   # Bitwise AND
  | "|"   # Bitwise OR
  | "^"   # Bitwise XOR
  | "<<"  # Left shift
  | ">>"  # Right shift

```

### Special Notes

Universal quantifier (ALL) and lambda abstraction (LAM) can use either "∀"/"λ" or "@" as their prefix.
The REF parser includes special handling for built-in types:

- "U64" → U64 type
- "F64" → F64 type
- "Set" → Set type
- "_" → Meta variable

Constructors in data types (DAT) can have multiple fields with named parameters.
Pattern matching (MAT) and switch expressions (SWI) use a lambda-like syntax with curly braces.
Type annotations can have an optional double colon (::) for stricter checking.


## Examples

To see examples of Kind usage, visit the [KindBook](https://github.com/HigherOrderCO/KindBook), which contains a collection of examples and tutorials.

### Basic Types

#### Bool

Defines the boolean type with two constructors:

```kind
Bool : * = #[]{
  #true{} : Bool
  #false{} : Bool
};
```

#### Nat

Defines the natural numbers type with two constructors:

```kind
Nat : * = #[]{
  #zero{} : Nat
  #succ{ pred: Nat } : Nat
};
```

### Predicates and Equality

#### IsTrue

A predicate that checks if a boolean is true:

```kind
IsTrue : ∀(b: Bool) * = λb #[b]{
  #indeed{} : (IsTrue #true{})
};
```

#### Equal

Defines equality between two values of the same type:

```kind
Equal : ∀(T: *) ∀(a: T) ∀(b: T) * = λT λa λb #[a b]{
  #refl{} : (Equal T a a)
};
```

### Functions

#### rewrite

A function that allows rewriting a value based on an equality proof:

```kind
rewrite
: ∀(T: *)
  ∀(a: T)
  ∀(b: T)
  ∀(e: (Equal T a b))
  ∀(P: ∀(x: A) *)
  ∀(x: (P a))
  (P b)
= λT λa λb λ{
  #refl: λP λx x
};
```
