//+------------------------------------------------------------------+
//|                                                        JAson.mqh |
//|                                                      (Simplified)|
//+------------------------------------------------------------------+
#property copyright "Public Domain"
#property version   "1.00"
#property strict

enum En_JAsonType { jtUNDEF, jtNULL, jtBOOL, jtINT, jtDBL, jtSTR, jtARRAY, jtOBJ };

class CJAVal {
public:
   virtual void Clear() { }
   virtual bool Deserialize(string json, int &i, string &err) { return false; }
   virtual En_JAsonType Type() { return jtUNDEF; }
   
   virtual string ToStr() { return ""; }
   virtual int ToInt() { return 0; }
   virtual double ToDbl() { return 0.0; }
   virtual bool ToBool() { return false; }
   
   virtual CJAVal* operator[](string key) { return NULL; }
   virtual CJAVal* operator[](int index) { return NULL; }
   virtual int Size() { return 0; }
};

class CJAValAtom : public CJAVal {
   string m_data;
   En_JAsonType m_type;
public:
   CJAValAtom(En_JAsonType t, string v) : m_type(t), m_data(v) { }
   virtual En_JAsonType Type() { return m_type; }
   virtual string ToStr() { return m_data; }
   virtual int ToInt() { return (int)StringToInteger(m_data); }
   virtual double ToDbl() { return StringToDouble(m_data); }
   virtual bool ToBool() { return m_data == "true"; }
};

class CJAValArray : public CJAVal {
   CJAVal* m_data[];
public:
   ~CJAValArray() { Clear(); }
   virtual void Clear() {
      for(int i=0; i<ArraySize(m_data); i++) if(CheckPointer(m_data[i])==POINTER_DYNAMIC) delete m_data[i];
      ArrayResize(m_data, 0);
   }
   virtual En_JAsonType Type() { return jtARRAY; }
   virtual int Size() { return ArraySize(m_data); }
   virtual CJAVal* operator[](int index) {
      if(index >= 0 && index < ArraySize(m_data)) return m_data[index];
      return NULL; 
   }
   void Add(CJAVal* item) {
      int s = ArraySize(m_data);
      ArrayResize(m_data, s+1);
      m_data[s] = item;
   }
};

class CJAValObj : public CJAVal {
   struct KeyVal { string key; CJAVal* val; };
   KeyVal m_data[];
public:
   ~CJAValObj() { Clear(); }
   virtual void Clear() {
      for(int i=0; i<ArraySize(m_data); i++) if(CheckPointer(m_data[i].val)==POINTER_DYNAMIC) delete m_data[i].val;
      ArrayResize(m_data, 0);
   }
   virtual En_JAsonType Type() { return jtOBJ; }
   virtual CJAVal* operator[](string key) {
      for(int i=0; i<ArraySize(m_data); i++) if(m_data[i].key == key) return m_data[i].val;
      return NULL;
   }
   void Add(string key, CJAVal* val) {
      int s = ArraySize(m_data);
      ArrayResize(m_data, s+1);
      m_data[s].key = key;
      m_data[s].val = val;
   }
};

class CJAson {
public:
   static CJAVal* Parse(string json) {
      int i = 0;
      string err = "";
      return ParseVal(json, i, err);
   }

private:
   static void SkipSpace(string &json, int &i) {
      while(i < StringLen(json)) {
         ushort c = StringGetCharacter(json, i);
         if(c == ' ' || c == '\t' || c == '\r' || c == '\n') i++;
         else break;
      }
   }

   static CJAVal* ParseVal(string &json, int &i, string &err) {
      SkipSpace(json, i);
      if(i >= StringLen(json)) return NULL;
      
      ushort c = StringGetCharacter(json, i);
      
      if(c == '{') return ParseObj(json, i, err);
      if(c == '[') return ParseArray(json, i, err);
      if(c == '"') return ParseStr(json, i, err);
      if(c == 't' || c == 'f') return ParseBool(json, i, err);
      if(c == 'n') return ParseNull(json, i, err);
      if((c >= '0' && c <= '9') || c == '-') return ParseNum(json, i, err);
      
      return NULL;
   }

   static CJAVal* ParseObj(string &json, int &i, string &err) {
      CJAValObj* obj = new CJAValObj();
      i++; // skip {
      SkipSpace(json, i);
      if(StringGetCharacter(json, i) == '}') { i++; return obj; } // empty
      
      while(true) {
         SkipSpace(json, i);
         if(StringGetCharacter(json, i) != '"') { delete obj; return NULL; }
         CJAVal* keyVal = ParseStr(json, i, err);
         string key = keyVal.ToStr();
         delete keyVal;
         
         SkipSpace(json, i);
         if(StringGetCharacter(json, i) != ':') { delete obj; return NULL; }
         i++; // skip :
         
         CJAVal* val = ParseVal(json, i, err);
         obj.Add(key, val);
         
         SkipSpace(json, i);
         ushort c = StringGetCharacter(json, i);
         if(c == '}') { i++; break; }
         if(c == ',') i++;
         else { delete obj; return NULL; }
      }
      return obj;
   }

   static CJAVal* ParseArray(string &json, int &i, string &err) {
      CJAValArray* arr = new CJAValArray();
      i++;
      SkipSpace(json, i);
      if(StringGetCharacter(json, i) == ']') { i++; return arr; }
      
      while(true) {
         CJAVal* val = ParseVal(json, i, err);
         arr.Add(val);
         
         SkipSpace(json, i);
         ushort c = StringGetCharacter(json, i);
         if(c == ']') { i++; break; }
         if(c == ',') i++;
         else { delete arr; return NULL; }
      }
      return arr;
   }

   static CJAVal* ParseStr(string &json, int &i, string &err) {
      string res = "";
      i++; 
      while(i < StringLen(json)) {
         ushort c = StringGetCharacter(json, i);
         if(c == '"') { i++; break; }
         if(c == '\\') {
            i++;
            c = StringGetCharacter(json, i);
            // Handle escapes briefly
         }
         res += ShortToString(c);
         i++;
      }
      return new CJAValAtom(jtSTR, res);
   }

   static CJAVal* ParseNum(string &json, int &i, string &err) {
      int start = i;
      while(i < StringLen(json)) {
         ushort c = StringGetCharacter(json, i);
         if((c >= '0' && c <= '9') || c == '.' || c == '-' || c == 'e' || c == 'E' || c == '+') i++;
         else break;
      }
      string numStr = StringSubstr(json, start, i-start);
      if(StringFind(numStr, ".") >= 0) return new CJAValAtom(jtDBL, numStr);
      return new CJAValAtom(jtINT, numStr);
   }

   static CJAVal* ParseBool(string &json, int &i, string &err) {
      if(StringSubstr(json, i, 4) == "true") { i+=4; return new CJAValAtom(jtBOOL, "true"); }
      if(StringSubstr(json, i, 5) == "false") { i+=5; return new CJAValAtom(jtBOOL, "false"); }
      return NULL;
   }

   static CJAVal* ParseNull(string &json, int &i, string &err) {
      if(StringSubstr(json, i, 4) == "null") { i+=4; return new CJAValAtom(jtNULL, "null"); }
      return NULL;
   }
};
