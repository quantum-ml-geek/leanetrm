using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.Json;
using OpenEtrm.MarketData.Crude;
using OpenEtrm.MarketData.Gas;
using OpenEtrm.MarketData.Trading;

// Published identity encodings are a contract independent of CLR inheritance.
internal static class RetainedInstrumentContractChecks
{
    internal static void Operating(RetainedOperatingInstrument instrument)=>Require(instrument,new JsonObject
    {
        ["contract"]="retained_operating_right_v1",["Currency"]=JsonNode.Parse(DefinitionIdentity.CanonicalTerm(instrument.Currency)),
        ["Members"]=OperatingMembers(instrument.Members),["Resource"]=JsonNode.Parse(DefinitionIdentity.CanonicalTerm(instrument.Resource)),
        ["UnitQuantity"]=JsonNode.Parse(DefinitionIdentity.CanonicalTerm(instrument.UnitQuantity))
    },string.Join('/',instrument.Members.Select(m=>m.ProgramDigest)));
    internal static void Rec(RetainedRecForwardInstrument instrument)=>Require(instrument,new JsonObject
    {
        ["contract"]="retained_rec_forward_v1",["Currency"]=JsonNode.Parse(DefinitionIdentity.CanonicalTerm(instrument.Currency)),
        ["Members"]=OperatingMembers(instrument.Members),["Product"]=JsonNode.Parse(DefinitionIdentity.CanonicalTerm(instrument.Product)),
        ["UnitQuantity"]=JsonNode.Parse(DefinitionIdentity.CanonicalTerm(instrument.UnitQuantity)),
        ["VintageFrom"]=instrument.VintageFrom.ToString("yyyy-MM-dd"),["VintageTo"]=instrument.VintageTo.ToString("yyyy-MM-dd")
    },string.Join('/',instrument.Members.Select(m=>m.ProgramDigest)));
    private static JsonArray OperatingMembers(IEnumerable<RetainedOperatingMember> members)
    {
        var values=new JsonArray();
        foreach(var m in members)values.Add(new JsonObject{["contract"]="retained_operating_member_v1",["Coefficient"]=m.Coefficient.ToString(),["ProgramDigest"]=m.ProgramDigest});
        return values;
    }
    internal static void Gas(RetainedGasInstrument instrument)
    {
        Missing("gas_membership",()=>_=new RetainedGasInstrument(Guid.NewGuid(),instrument.Members,[]));
        Sides(instrument,[..instrument.Members.Select(m=>(m.SideId,m.Program,m.Direction,(OpenEtrm.Shared.Numerics.ExactRatio?)m.Ratio))]);
        var members = new JsonArray();
        foreach (var m in instrument.Members) members.Add(new JsonObject
        {
            ["contract"] = "retained_gas_member_v1", ["Direction"] = m.Direction.ToString(), ["ProgramDigest"] = m.ProgramDigest,
            ["Ratio"] = new JsonArray("exact_ratio", m.Ratio.Numerator.ToString(), m.Ratio.Denominator.ToString())
        });
        var assignments = new JsonArray();
        foreach (var a in instrument.Assignments) assignments.Add(JsonNode.Parse(DefinitionIdentity.For(a).Canonical));
        Require(instrument, new JsonObject { ["contract"] = "retained_gas_instrument_v1", ["Assignments"] = assignments, ["Members"] = members },
            string.Join('/', instrument.Members.Select(m => m.ProgramDigest)));
    }
    internal static void Crude(RetainedCrudeInstrument instrument)
    {
        Missing("crude_membership",()=>_=new RetainedCrudeInstrument(Guid.NewGuid(),null!,instrument.Members));
        Sides(instrument,[..instrument.Members.Select(m=>(m.SideId,m.Program,m.Coefficient,(OpenEtrm.Shared.Numerics.ExactRatio?)null))]);
        var members = new JsonArray();
        foreach (var m in instrument.Members) members.Add(new JsonObject
        {
            ["contract"] = "retained_crude_member_v1", ["Coefficient"] = m.Coefficient.ToString(), ["ProgramDigest"] = m.ProgramDigest
        });
        Require(instrument, new JsonObject { ["contract"] = "retained_crude_instrument_v1",
            ["Assignment"] = JsonNode.Parse(DefinitionIdentity.For(instrument.Assignment).Canonical), ["Members"] = members },
            string.Join('/', instrument.Members.Select(m => m.ProgramDigest)));
    }
    internal static void Sides(Instrument instrument,(Guid Id,BookedSideProgram Program,OpenEtrm.MarketData.ExactDecimal Coefficient,OpenEtrm.Shared.Numerics.ExactRatio? Ratio)[] members)
    {
        if(instrument is not SidedInstrument composed||composed.Sides.Length!=members.Length)
            throw new Exception("A retained instrument must delegate to real Sides for every original booked program, without rebuilding its schedule.");
        CanonicalOther(instrument);
        Copies(composed);
        for(var n=0;n<members.Length;n++)
        {
            var actual=composed.Sides[n];var expected=members[n];
            if(!ReferenceEquals(actual.Side.GenerateSchedule(),actual.Side.GenerateSchedule()))
                throw new Exception("A retained Side must reuse its immutable program schedule wrapper rather than allocate inspection rows for every scenario PV.");
            var structural=RetainedProgramSide.Define(expected.Id,expected.Program,instrument.UnitQuantity,instrument.Currency);
            if(structural.Id!=actual.Side.Id||DefinitionIdentity.For(structural)!=DefinitionIdentity.For(actual.Side))
                throw new Exception("Unpriced retained structure and bound execution must use the same genuine Side definition and exact program identity.");
            using var saved=JsonDocument.Parse(expected.Program.Document.EconomicIdentity);
            if(actual.Side is not RetainedProgramSide retained || !retained.Program.Write().AsSpan().SequenceEqual(expected.Program.Write()) ||
                retained.GenerateSchedule().Rows.Any(row=>row.ProgramReference is not {} address||!address.Program.Write().AsSpan().SequenceEqual(expected.Program.Write())) ||
                actual.Side.Id!=expected.Id||actual.Coefficient!=expected.Coefficient||actual.QuantityRatio!=expected.Ratio||
                DefinitionIdentity.For(actual.Side.CalendarPolicy).Canonical!=saved.RootElement.GetProperty("CalendarPolicy").GetRawText())
                throw new Exception("Retained Sides must preserve exact member order, native IDs, signs, ratios and captured calendars.");
        }
    }
    private static void Copies(SidedInstrument instrument)
    {
        // Prime the identity/interner before presenting an inconsistent copy:
        // validation must precede economic deduplication and cache reuse.
        _=instrument.EconomicIdentity;
        var map=new InstrumentIdentityMap(Guid.NewGuid());map.Intern(instrument);
        var changed=instrument with{Sides=instrument.Sides.SetItem(0,instrument.Sides[0] with{Coefficient=instrument.Sides[0].Coefficient*OpenEtrm.MarketData.ExactDecimal.Parse("-1")})};
        var reversed=instrument with{Sides=[..instrument.Sides.Reverse()]};
        foreach(var invalid in instrument.Sides.SequenceEqual(reversed.Sides)?new[]{changed}:new[]{changed,reversed})
        {
            Refuse(()=>_=invalid.EconomicIdentity);
            Refuse(()=>_=DefinitionIdentity.For(invalid));
            Refuse(()=>_=map.Intern(invalid));
        }
        static void Refuse(Action read)
        {
            try{read();}catch(OpenEtrm.MarketData.MarketDataException error)when(error.Code=="retained_side_composition"){return;}
            throw new Exception("An altered or reordered retained Side copy must refuse before economic identity, interning or cached reuse.");
        }
    }
    private static void CanonicalOther(Instrument instrument)
    {
        if(instrument is OpenEtrm.MarketData.Lng.RetainedLngInstrument source)
            Missing("lng_membership",()=>_=new OpenEtrm.MarketData.Lng.RetainedLngInstrument(Guid.NewGuid(),null!,source.Incoterms,source.Members));
        JsonArray Members<T>(System.Collections.Immutable.ImmutableArray<T> rows,string contract) where T:IRetainedProgramMember
        {
            var values=new JsonArray();
            foreach(var row in rows)values.Add(new JsonObject{["contract"]=contract,["Coefficient"]=row.ValuationCoefficient.ToString(),["ProgramDigest"]=row.ProgramDigest});
            return values;
        }
        JsonNode Term(object term)=>JsonNode.Parse(DefinitionIdentity.For(term).Canonical)!;
        JsonArray Reference(OpenEtrm.MarketData.ReferenceKey key)=>new("reference",new JsonArray("reference_revision",key.Revision.CatalogId.ToString(),key.Revision.RevisionId.ToString()),key.Code);
        JsonArray Quantity(OpenEtrm.MarketData.Quantity q)=>new("quantity",q.Amount.ToString(),Reference(q.Specification));
        JsonObject? expected=instrument switch
        {
            OpenEtrm.MarketData.Lng.RetainedLngInstrument lng=>new(){["contract"]="retained_lng_instrument_v1",["Assignment"]=Term(lng.Assignment),["Incoterms"]=Term(lng.Incoterms),["Members"]=Members(lng.Members,"retained_lng_member_v1")},
            RetainedOperatingInstrument operating=>new(){["contract"]="retained_operating_right_v1",["Currency"]=Reference(operating.Currency),["Members"]=Members(operating.Members,"retained_operating_member_v1"),
                ["Resource"]=new JsonArray("asset",new JsonArray("definition_revision",operating.Resource.Revision.CatalogId.ToString(),operating.Resource.Revision.RevisionId.ToString()),operating.Resource.Code),["UnitQuantity"]=Quantity(operating.UnitQuantity)},
            RetainedRecForwardInstrument rec=>new(){["contract"]="retained_rec_forward_v1",["Currency"]=Reference(rec.Currency),["Members"]=Members(rec.Members,"retained_operating_member_v1"),["Product"]=Reference(rec.Product),
                ["UnitQuantity"]=Quantity(rec.UnitQuantity),["VintageFrom"]=rec.VintageFrom.ToString("yyyy-MM-dd"),["VintageTo"]=rec.VintageTo.ToString("yyyy-MM-dd")},
            _=>null
        };
        if(expected is not null)Require(instrument,expected,string.Join('/',((SidedInstrument)instrument).Sides.Select(m=>((RetainedProgramSide)m.Side).ProgramDigest)));
    }
    private static void Missing(string code,Action construct)
    {
        try{construct();}catch(OpenEtrm.MarketData.MarketDataException error)when(error.Code==code){return;}
        throw new Exception("Missing retained source terms must keep their structured membership refusal before derived Side construction.");
    }
    private static void Require(Instrument instrument, JsonObject expected, string programs)
    {
        var canonical = expected.ToJsonString();
        if (instrument.EconomicIdentity.Canonical != canonical || instrument.EconomicIdentity.Digest != Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(canonical))) ||
            instrument.RetainedScheduleIdentity != "retained_side_programs_v1/" + programs)
            throw new Exception("Retained instrument identity bytes, digest and ordered program identity must remain compatible.");
    }
}
