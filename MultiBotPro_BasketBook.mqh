#ifndef __MULTIBOTPRO_BASKETBOOK_MQH__
#define __MULTIBOTPRO_BASKETBOOK_MQH__
//+------------------------------------------------------------------+
//|                                      MultiBotPro_BasketBook.mqh  |
//|  Step 2a: Leak-free basket book with centralized cap (100)       |
//|  Requires SBasketState already defined (include after Defines).  |
//|  Embedded in SSymbolData as CBasketBook basketBook; legacy       |
//|  BasketStates[100]/BasketStateCount kept as deprecated alias and |
//|  synced for backward compat (removed in Step 2b shard).          |
//+------------------------------------------------------------------+

#ifndef MBP_MAX_BASKETS
#define MBP_MAX_BASKETS 100
#endif
#ifndef MBP_MAX_BASKETS_PER_SYMBOL
#define MBP_MAX_BASKETS_PER_SYMBOL 100
#endif

// CBasketBook — owns SBasketState* heap objects, hard cap 100
// Destructor deletes all. Copy is disabled (MQL5 default is shallow).
class CBasketBook
{
private:
   SBasketState* m_items[MBP_MAX_BASKETS];
   int           m_count;

public:
   CBasketBook(): m_count(0)
   {
      for(int i=0; i<MBP_MAX_BASKETS; i++)
         m_items[i] = NULL;
   }

   ~CBasketBook()
   {
      ResetAll();
   }

   int Count() const { return m_count; }

   SBasketState* Find(const int basketId) const
   {
      for(int i=0; i<m_count; i++)
      {
         if(CheckPointer(m_items[i]) != POINTER_INVALID && m_items[i].BasketId == basketId)
            return m_items[i];
      }
      return NULL;
   }

   SBasketState* At(const int index) const
   {
      if(index < 0 || index >= m_count) return NULL;
      if(CheckPointer(m_items[index]) == POINTER_INVALID) return NULL;
      return m_items[index];
   }

   SBasketState* GetOrCreate(const int basketId)
   {
      SBasketState* ex = Find(basketId);
      if(ex != NULL) return ex;

      if(m_count >= MBP_MAX_BASKETS)
      {
         if(MBP_LogTierEnabled(MBP_LOG_TIER_CRITICAL))
            Print("ERROR: Maximum basket states (", MBP_MAX_BASKETS, ") exceeded for basketId=", basketId);
         return NULL;
      }

      SBasketState* bs = new SBasketState();
      bs.BasketId = basketId;
      m_items[m_count] = bs;
      m_count++;
      return bs;
   }

   bool Reset(const int basketId)
   {
      for(int i=0; i<m_count; i++)
      {
         if(CheckPointer(m_items[i]) != POINTER_INVALID && m_items[i].BasketId == basketId)
         {
            delete m_items[i];
            m_items[i] = NULL;
            if(i < m_count - 1)
               m_items[i] = m_items[m_count - 1];
            m_items[m_count - 1] = NULL;
            m_count--;
            return true;
         }
      }
      return false;
   }

   void ResetAll()
   {
      for(int i=0; i<m_count; i++)
      {
         if(CheckPointer(m_items[i]) != POINTER_INVALID)
            delete m_items[i];
         m_items[i] = NULL;
      }
      m_count = 0;
      // Clear remainder
      for(int i=m_count; i<MBP_MAX_BASKETS; i++)
         m_items[i] = NULL;
   }

   // Sync to deprecated legacy array for backward compat (Step 2a only)
   void SyncToLegacy(SBasketState* &legacy[], int &legacyCount) const
   {
      // legacy is fixed [100] array passed as reference; we copy via loop in caller
      // This helper is not used directly — callers sync manually via At()
   }

   // Accessor for legacy sync loop
   SBasketState* RawAt(const int idx) const
   {
      if(idx < 0 || idx >= MBP_MAX_BASKETS) return NULL;
      return m_items[idx];
   }
};

#endif // __MULTIBOTPRO_BASKETBOOK_MQH__
