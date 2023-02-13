use interner::Interner;
use std::hash::Hash;
use std::ops::Range;

mod interner;

pub type Spanned<T> = (T, Span);

#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
/// A index key to a source code.
pub struct SyntaxCtxIndex(pub usize);

/// A symbol is a index in the symbol interner. It's useful for
/// O(1) comparison and to avoid copies.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Symbol(pub u32);

impl Symbol {
    #[inline]
    pub fn intern(str: &str) -> Self {
        Interner::intern(str)
    }

    #[inline]
    pub fn to_str(&self) -> &'static str {
        Interner::get_string(self)
    }
}

impl ToString for Symbol {
    #[inline]
    fn to_string(&self) -> String {
        Interner::get_string(self).to_string()
    }
}

/// A location between two byte positions inside a string.
pub type Span = Range<usize>;

#[derive(Hash, PartialEq, Eq)]
pub enum NodeIdSegment {
    Symbol(u32),
    Index(u32),
}

impl From<Symbol> for NodeIdSegment {
    #[inline]
    fn from(value: Symbol) -> Self {
        NodeIdSegment::Symbol(value.0)
    }
}

/// A node identifier is a sequence of node identifier segments so each
/// identifier can form a tree like structure that is easier
pub struct NodeId {
    data: Vec<NodeIdSegment>,
    hash: u64,
}

impl PartialEq for NodeId {
    fn eq(&self, other: &Self) -> bool {
        self.hash == other.hash
    }
}

impl Eq for NodeId {
    fn assert_receiver_is_total_eq(&self) {}
}

impl Hash for NodeId {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        self.hash.hash(state);
    }
}

impl NodeId {
    pub fn new(data: Vec<NodeIdSegment>) -> Self {
        NodeId {
            hash: fxhash::hash64(&data),
            data,
        }
    }

    pub fn segments(&self) -> &[NodeIdSegment] {
        &self.data
    }
}
