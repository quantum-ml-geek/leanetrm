using OpenEtrm.Api;
using OpenEtrm.MarketData;

internal static class PointTraderMarkIdentityChecks
{
    internal static void Run()
    {
        var point=new PointTraderMarkPoint(Guid.Parse("11111111-1111-1111-1111-111111111111"),
            Guid.Parse("22222222-2222-2222-2222-222222222222"),Guid.Parse("33333333-3333-3333-3333-333333333333"),
            "synthetic_marks",DateTimeOffset.Parse("2020-12-19T16:00:00Z"));
        var first=PointTraderMarkIdentity.Event(point);
        Equal("manual_point_event_v1:aa3a46ea0f3bbcff426d35997be62055325720d4d204f3ddc7d5bfaf806b3dd6",first);
        Equal("manual_point_revision_v1:54861ecc22b49b11f9f70d24e23c2765c5e1cf3b59ac011518a53cd7ee5b266d",
            PointTraderMarkIdentity.Revision(point,first,null));
        var previous=Guid.Parse("44444444-4444-4444-4444-444444444444");
        // These expected identities are independently generated UTF-8 vectors.
        foreach(var(entry,expected)in new[]{
            (" synthetic:é🙂:event ","7eb91ec132dca0c64cb25d695cc315e147928b1ef69be41aa06ad29f30fc4e07"),
            ("synthetic\nevent","66051651b652e47170591ba80f335d6c97ff735217f6e5f9658f5a059b8fc854"),
            ("synthetic:e\u0301","87b15bf1cf7e2411c7ecf8b667c99a6046c0b7bfcea7311ce3651ad8824ad5c9"),
            ("synthetic:é","82f72034b99e1cfa9a72cb9081b9c511b41faa4db1e5e10c3179fa070f967523")})
            Equal("manual_point_revision_v1:"+expected,PointTraderMarkIdentity.Revision(point,entry,previous));
        Equal("manual_point_event_v1:3a97ab6e1cddb17d56b7eed347151e0931a22f04729d2cad6efad6ae47dcd617",
            PointTraderMarkIdentity.Event(point with{ObservedAt=DateTimeOffset.Parse("2020-12-19T16:00:00.000001Z")}));
        Equal("manual_point_event_v1:7f2babeb6d3169c435d3f38e268d9496d9576c681bfc1f9ebf1b67df474d2b6b",
            PointTraderMarkIdentity.Event(point with{ObservedAt=DateTimeOffset.Parse("2020-12-19T16:00:00.120000Z")}));
        if(PointTraderMarkIdentity.Revision(point,first,previous)==PointTraderMarkIdentity.Revision(point,first,null))
            throw new Exception("A new selected predecessor must identify a new explicit manual revision.");
        Reject(()=>PointTraderMarkIdentity.Event(point with{CatalogId=Guid.Empty}));
        Reject(()=>PointTraderMarkIdentity.Event(point with{DefinitionRevisionId=Guid.Empty}));
        Reject(()=>PointTraderMarkIdentity.Event(point with{SeriesId=Guid.Empty}));
        Reject(()=>PointTraderMarkIdentity.Event(point with{Source=""}));
        Reject(()=>PointTraderMarkIdentity.Event(point with{ObservedAt=point.ObservedAt.AddTicks(1)}));
        Reject(()=>PointTraderMarkIdentity.Event(point with{ObservedAt=point.ObservedAt.ToOffset(TimeSpan.FromHours(1))}));
        Reject(()=>PointTraderMarkIdentity.Revision(point,"",previous));
        Reject(()=>PointTraderMarkIdentity.Revision(point,"synthetic\0event",previous));
        Reject(()=>PointTraderMarkIdentity.Revision(point,"\ud800",previous));
        Reject(()=>PointTraderMarkIdentity.Revision(point,first,Guid.Empty));
        Console.WriteLine("PASS manual point identity: independent UTF-8 vectors, opaque imported events, explicit predecessor and exact UTC microseconds");
    }
    static void Equal(string expected,string actual)
    {if(expected!=actual)throw new Exception("The manual point identity differs from its independent source-event/revision vector.");}
    static void Reject(Action action)
    {
        try{action();throw new Exception("A malformed point identity was accepted.");}
        catch(MarketDataException error)when(error.Code=="point_trader_mark_input"){}
    }
}
